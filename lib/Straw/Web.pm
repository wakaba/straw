package Straw::Web;
use strict;
use warnings;
use Path::Tiny;
use Promise;
use Promised::File;
use Promised::Command::Signals;
use JSON::PS;
use Wanage::HTTP;
use Warabe::App;
use Dongry::Database;
use Dongry::Type;
use Dongry::Type::JSONPS;
use Straw::Fetch;
use Straw::Stream;
use Straw::Process;
use Straw::Worker;
use Straw::Sink;

my $config_path = path ($ENV{APP_CONFIG} // die "Bad |APP_CONFIG|");
my $config = json_bytes2perl $config_path->slurp;

my $DBSources = {master => {dsn => Dongry::Type->serialize ('text', $config->{alt_dsns}->{master}->{straw}),
                            writable => 1, anyevent => 1},
                 default => {dsn => Dongry::Type->serialize ('text', $config->{dsns}->{straw}),
                             anyevent => 1}};

my $IndexFile = Promised::File->new_from_path
    (path (__FILE__)->parent->parent->parent->child ('index.html'));

my $Worker;
my $Signals = {};

sub psgi_app ($) {
  my ($class) = @_;

  {
    $Worker = Straw::Worker->new_from_db_sources ($DBSources);
    $Worker->run ('fetch');
    $Worker->run ('process');

    $Signals->{TERM} = Promised::Command::Signals->add_handler (TERM => sub {
      $Worker->terminate;
      undef $Worker;
      %$Signals = ();
    });
    $Signals->{INT} = Promised::Command::Signals->add_handler (INT => sub {
      $Worker->terminate;
      undef $Worker;
      %$Signals = ();
    });
    $Signals->{QUIT} = Promised::Command::Signals->add_handler (QUIT => sub {
      $Worker->terminate;
      undef $Worker;
      %$Signals = ();
    });
  }

  return sub {
    ## This is necessary so that different forked siblings have
    ## different seeds.
    srand;

    ## XXX Parallel::Prefork (?)
    delete $SIG{CHLD};
    delete $SIG{CLD};

    my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
    my $app = Warabe::App->new_from_http ($http);

    # XXX accesslog
    warn sprintf "Access: [%s] %s %s\n",
        scalar gmtime, $app->http->request_method, $app->http->url->stringify;

    my $db = Dongry::Database->new (sources => $DBSources);

    return $app->execute_by_promise (sub {
      return Promise->resolve->then (sub {
        return $class->main ($app, $db);
      })->then (sub {
        return $db->disconnect;
      }, sub {
        my $e = $_[0];
        return $db->disconnect->then (sub { die $e }, sub { die $e });
      });
    });
  };
} # psgi_app

sub main ($$$) {
  my ($class, $app, $db) = @_;
  my $path = $app->path_segments;

  if (@$path >= 2 and
      $path->[0] eq 'source' and $path->[1] =~ /\A[0-9]+\z/) {
    if (@$path == 2) {
      # /source/{source_id}
      my $fetch = Straw::Fetch->new_from_db ($db);
      if ($app->http->request_method eq 'POST') {
        # XXX CSRF
        my $result = {};
        return $fetch->save_fetch_source
            ($path->[1],
             (json_bytes2perl $app->bare_param ('fetch_options') // ''),
             (json_bytes2perl $app->bare_param ('schedule_options') // ''),
             $result)->then (sub {
          $Worker->run ('fetch') # don't return
              if defined $result->{next_fetch_time};
          return $class->send_json ($app, {});
        }, sub {
          if (ref $_[0] eq 'HASH') {
            return $app->throw_error
                ($_[0]->{status}, reason_phrase => $_[0]->{reason});
          } else {
            die $_[0];
          }
        });
      } else { # GET
        return $fetch->load_fetch_source_by_id ($path->[1])->then (sub {
          my $source = $_[0];
          if (defined $source) {
            $source->{fetch_options} = json_bytes2perl $source->{fetch_options};
            $source->{schedule_options} = json_bytes2perl $source->{schedule_options};
            return $class->send_json
                ($app, {type => 'fetch_source', fetch => $source});
          } else {
            return $app->send_error (404, reason_phrase => 'Source not found');
          }
        });
      }
    } elsif (@$path == 3 and $path->[2] eq 'enqueue') {
      # /source/{source_id}/enqueue
      $app->requires_request_method ({POST => 1});
      # XXX CSRF
      my $fetch = Straw::Fetch->new_from_db ($db);
      return $fetch->load_fetch_source_by_id ($path->[1])->then (sub {
        my $source = $_[0];
        return $app->throw_error (404, source_name => 'Fetch source not found')
            unless defined $source;
        # XXX don't insert if time - fetch_result.timestamp < threshold
        return $fetch->add_fetch_task
            (Dongry::Type->parse ('json', $source->{fetch_options}));
        #XXX then, add schedule_task
      })->then (sub {
        $app->http->set_status (202);
        $class->send_json ($app, {});
        $Worker->run ('fetch');
      });
    } elsif (@$path == 3 and $path->[2] eq 'fetched') { # XXX debug only
      # /source/{source_id}/fetched
      my $fetch = Straw::Fetch->new_from_db ($db);
      return $fetch->load_fetch_source_by_id ($path->[1])->then (sub {
        my $source = $_[0];
        return $app->throw_error (404, source_name => 'Fetch source not found')
            unless defined $source;
        return $fetch->load_fetch_result ($source->{fetch_key})->then (sub {
          return $app->send_error (404, reason_phrase => 'No fetch result')
              unless defined $_[0];
          $app->http->set_response_header
              ('Content-Type' => 'message/http');
          $app->http->set_response_header
              ('Content-Disposition' => 'attachment');
          $app->http->set_response_header
              ('Content-Security-Policy' => 'sandbox');
          $app->http->send_response_body_as_ref (\($_[0]));
          return $app->http->close_response_body;
        });
      });
    }
  } elsif (@$path == 1 and $path->[0] eq 'source') {
    # /source
    $app->requires_request_method ({POST => 1});
    # XXX CSRF
    my $type = $app->bare_param ('type') // '';
    return $app->throw_error (400, reason_phrase => 'Bad |type|')
        unless $type eq 'fetch_source';
    my $fetch = Straw::Fetch->new_from_db ($db);
    my $result = {};
    return $fetch->save_fetch_source
        (undef,
         (json_bytes2perl ($app->bare_param ('fetch_options') // '')),
         (json_bytes2perl ($app->bare_param ('schedule_options') // '')),
         $result)->then (sub {
      $Worker->run ('fetch') # don't return
          if defined $result->{next_fetch_time};
      return $class->send_json ($app, {source_id => $_[0]});
    }, sub {
      if (ref $_[0] eq 'HASH') {
        return $app->throw_error
            ($_[0]->{status}, reason_phrase => $_[0]->{reason});
      } else {
        die $_[0];
      }
    });
  } elsif (@$path == 2 and $path->[0] eq 'source' and $path->[1] eq 'logs') {
    # /source/logs
    my $fetch = Straw::Fetch->new_from_db ($db);
    my $after = $app->bare_param ('after') || 0;
    return $fetch->load_error_logs (after => $after)->then (sub {
      my $items = $_[0];
      my $next_after = @$items ? $items->[-1]->{timestamp} : $after;
      return $class->send_json ($app, {
        next_after => $next_after,
        next_url => $app->http->url->resolve_string ('logs?after=' . $next_after)->stringify,
        items => $items,
      });
    });
  }

  if (@$path >= 2 and
      $path->[0] eq 'process' and $path->[1] =~ /\A[0-9]+\z/) {
    if (@$path == 2) {
      # /process/{process_id}
      my $process = Straw::Process->new_from_db ($db);
      return $process->load_process_by_id ($path->[1])->then (sub {
        my $data = $_[0];
        return $app->throw_error (404, reason_phrase => 'Process not found')
            unless defined $data;
        $data->{process_options} = json_bytes2perl $data->{process_options};
        return $class->send_json ($app, $data);
      });
    }
  } elsif (@$path == 1 and $path->[0] eq 'process') {
    # /process
    $app->requires_request_method ({POST => 1});
    # XXX CSRF
    my $process = Straw::Process->new_from_db ($db);
    return $process->save_process ((json_bytes2perl ($app->bare_param ('process_options') // '')))->then (sub {
      my $process_id = $_[0];
      return $class->send_json ($app, {process_id => $process_id});
    }, sub {
      if (ref $_[0] eq 'HASH') {
        return $app->throw_error
            ($_[0]->{status}, reason_phrase => $_[0]->{reason});
      } else {
        die $_[0];
      }
    });
  } elsif (@$path == 2 and $path->[0] eq 'process' and $path->[1] eq 'logs') {
    # /process/logs
    my $process = Straw::Process->new_from_db ($db);
    my $after = $app->bare_param ('after') || 0;
    return $process->load_error_logs (after => $after)->then (sub {
      my $items = $_[0];
      my $next_after = @$items ? $items->[-1]->{timestamp} : $after;
      return $class->send_json ($app, {
        next_after => $next_after,
        next_url => $app->http->url->resolve_string ('logs?after=' . $next_after)->stringify,
        items => $items,
      });
    });
  }

  if (@$path >= 2 and
      $path->[0] eq 'stream' and $path->[1] =~ /\A[0-9]+\z/) {
    if (@$path == 2) {
      # /stream/{stream_id}
      my $stream = Straw::Stream->new_from_db ($db);
      return $stream->load_stream_by_id ($path->[1])->then (sub {
        my $data = $_[0];
        return $app->throw_error (404, reason_phrase => 'Stream not found')
            unless defined $data;
        return $class->send_json ($app, $data);
      });
    }
  } elsif (@$path == 1 and $path->[0] eq 'stream') {
    # /stream
    $app->requires_request_method ({POST => 1});
    # XXX CSRF
    my $stream = Straw::Stream->new_from_db ($db);
    return $stream->save_stream->then (sub {
      my $stream_id = $_[0];
      return $class->send_json ($app, {stream_id => $stream_id});
    });
  }

  if (@$path >= 2 and
      $path->[0] eq 'sink' and $path->[1] =~ /\A[0-9]+\z/) {
    if (@$path == 2) {
      # /sink/{sink_id}
      my $sink = Straw::Sink->new_from_db ($db);
      if ($app->http->request_method eq 'POST') {
        # XXX CSRF
        return $sink->save_sink
            ($path->[1],
             $app->bare_param ('stream_id'),
             $app->bare_param ('channel_id'))->then (sub {
          return $class->send_json ($app, {});
        }, sub {
          if (ref $_[0] eq 'HASH') {
            return $app->throw_error
                ($_[0]->{status}, reason_phrase => $_[0]->{reason});
          } else {
            die $_[0];
          }
        });
      } else { # GET
        return $sink->load_sink_by_id ($path->[1])->then (sub {
          my $data = $_[0];
          return $app->throw_error (404, reason_phrase => 'Sink not found')
              unless defined $data;
          return $class->send_json ($app, $data);
        });
      }
    } elsif (@$path == 3 and $path->[2] eq 'items') {
      # /sink/{sink_id}/items
      my $sink = Straw::Sink->new_from_db ($db);
      return $sink->load_sink_by_id ($path->[1])->then (sub {
        my $data = $_[0];
        return $app->throw_error (404, reason_phrase => 'Sink not found')
            unless defined $data;
        my $stream = Straw::Stream->new_from_db ($db);
        my $after = $app->bare_param ('after') || 0;
        return $stream->load_item_data
            (stream_id => $data->{stream_id},
             channel_id => $data->{channel_id},
             after => $after)->then (sub {
          my $items = $_[0];
          my $next_after = @$items ? $items->[-1]->{timestamp} : $after;
          return $class->send_json ($app, {
            next_after => $next_after,
            next_url => $app->http->url->resolve_string
                ('items?after=' . $next_after)->stringify,
            items => $items,
          });
        });
      });
    }
  } elsif (@$path == 1 and $path->[0] eq 'sink') {
    # /sink
    $app->requires_request_method ({POST => 1});
    # XXX CSRF
    my $sink = Straw::Sink->new_from_db ($db);
    return $sink->save_sink
        (undef,
         $app->bare_param ('stream_id'), $app->bare_param ('channel_id'))->then (sub {
      my $sink_id = $_[0];
      return $class->send_json ($app, {sink_id => $sink_id});
    }, sub {
      if (ref $_[0] eq 'HASH') {
        return $app->throw_error
            ($_[0]->{status}, reason_phrase => $_[0]->{reason});
      } else {
        die $_[0];
      }
    });
  }

  if (@$path == 1 and $path->[0] eq '') {
    # /
    return $IndexFile->read_byte_string->then (sub {
      $app->http->set_response_header
          ('Content-Type' => 'text/html; charset=utf-8');
      $app->http->send_response_body_as_ref (\($_[0]));
      return $app->http->close_response_body;
    });
  }

  # XXX is_test and
  if (@$path == 2 and $path->[0] eq 'test' and $path->[1] eq 'queue') {
    # /test/queue
    return $db->execute ('select fetch_key from fetch_task limit 1')->then (sub {
      return $class->send_json ($app, {empty => 0}) if $_[0]->first;
      return $db->execute ('select process_id from process_task limit 1')->then (sub {
        return $class->send_json ($app, {
          empty => $_[0]->first ? 0 : 1,
        });
      });
    });
  }

  return $app->send_error (404);
} # main

sub send_json ($$$) {
  my ($class, $app) = @_;
  $app->http->set_response_header
      ('Content-Type', 'application/json; charset=utf-8');
  $app->http->send_response_body_as_text (perl2json_chars_for_record $_[2]);
  $app->http->close_response_body;
} # send_json

1;

=head1 LICENSE

Copyright 2015-2016 Wakaba <wakaba@suikawiki.org>.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Affero General Public License for more details.

You does not have received a copy of the GNU Affero General Public
License along with this program, see <http://www.gnu.org/licenses/>.

=cut
