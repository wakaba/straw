package Straw::Web;
use strict;
use warnings;
use Path::Tiny;
use Promise;
use Promised::Command::Signals;
use JSON::PS;
use Wanage::HTTP;
use Warabe::App;
use Dongry::Database;
use Dongry::Type;
use Dongry::Type::JSONPS;
use Straw::Action;
use Straw::Fetch;
use Straw::Worker;

my $config_path = path ($ENV{APP_CONFIG} // die "Bad |APP_CONFIG|");
my $config = json_bytes2perl $config_path->slurp;

my $DBSources = {master => {dsn => Dongry::Type->serialize ('text', $config->{alt_dsns}->{master}->{straw}),
                            writable => 1, anyevent => 1},
                 default => {dsn => Dongry::Type->serialize ('text', $config->{dsns}->{straw}),
                             anyevent => 1}};

my $Worker;
my $Signals = {};

sub psgi_app ($) {
  my ($class) = @_;

  {
    $Worker = Straw::Worker->new_from_db_sources ($DBSources);
    $Worker->run;

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
        return $fetch->save_fetch_source
            ($path->[1],
             (json_bytes2perl $app->bare_param ('fetch_options') // ''),
             (json_bytes2perl $app->bare_param ('schedule_options') // ''))->then (sub {
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
        $Worker->run;
      });
    } elsif (@$path == 3 and $path->[2] eq 'fetched') {
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
    return $fetch->save_fetch_source
        (undef,
         (json_bytes2perl $app->bare_param ('fetch_options') // ''),
         (json_bytes2perl $app->bare_param ('schedule_options') // ''))->then (sub {
      return $class->send_json ($app, {source_id => $_[0]});
    }, sub {
      if (ref $_[0] eq 'HASH') {
        return $app->throw_error
            ($_[0]->{status}, reason_phrase => $_[0]->{reason});
      } else {
        die $_[0];
      }
    });
  }

  if (@$path >= 2 and
      $path->[0] eq 'stream' and $path->[1] =~ /\A[0-9]+\z/) {

    if (@$path == 3 and $path->[2] eq 'items') {
      # /stream/{stream_id}/items
      my $act = Straw::Action->new_from_db ($db);
      return $act->load_for_export ($path->[1])->then (sub {
        return $class->send_json ($app, $_[0]);
      });
    }

    if (@$path == 3 and $path->[2] eq 'run') {
      # /stream/{stream_id}/run
      return $app->send_error (405)
          unless $app->http->request_method eq 'POST';
      # XXX CSRF
      my $act = Straw::Action->new_from_db ($db);
      return Promise->resolve->then (sub {
        #return $act->enqueue_stream_processes ([$path->[1]], 0);
      })->then (sub {
        return $act->schedule_fetch_by_stream_id ($path->[1]);
      })->then (sub {
        return $class->send_json ($app, {});
      });
    }

    if (@$path == 3 and $path->[2] eq 'edit') {
      # /stream/{stream_id}/edit
      # XXX {stream_id} not found
      return $app->send_html (q{
        <!DOCTYPE html>
        <title>Edit</title>
        <form action=javascript: method=post>
          <p><textarea name=data></textarea>
          <p><button type=submit>Save</button>
          <p><button type=button class=run-button onclick="
            var f = document.createElement ('form');
            f.method = 'POST';
            f.action = 'run';
            f.target = 'result';
            f.submit ();
          ">Run</button>
          <iframe name=result></iframe>
          <script>
            fetch ('edit.json').then (function (res) {
              return res.text ();
            }).then (function (s) {
              document.forms[document.forms.length-1].elements.data.value = s;
            });
            var form = document.forms[document.forms.length-1];
            form.onsubmit = function () {
              var submits = Array.prototype.slice (this.querySelectorAll ('[type=submit]'));
              submits.forEach (function (x) { x.disabled = true });
              var fd = new FormData (this);
              fetch ('edit.json', {body: fd, method: 'POST'}).then (function (res) {
                submits.forEach (function (x) { x.disabled = false });
              });
              return false;
            };
          </script>
        </form>
      });
    }

    if (@$path == 3 and $path->[2] eq 'edit.json') {
      # /stream/{stream_id}/edit.json
      # XXX stream not found
      # XXX access control
      if ($app->http->request_method eq 'POST') {
        # XXX CSRF
        my $data = json_bytes2perl $app->bare_param ('data') // '';
        return $app->send_error (400) unless defined $data;
        my $time = time;
        return $db->insert ('stream_process', [{
          stream_id => Dongry::Type->serialize ('text', $path->[1]),
          data => Dongry::Type->serialize ('json', $data),
          created => $time,
          updated => $time,
        }], duplicate => {
          data => $db->bare_sql_fragment ('VALUES(data)'),
          updated => $db->bare_sql_fragment ('VALUES(updated)'),
        })->then (sub {
          my $act = Straw::Action->new_from_db ($db);
          return $act->update_subscriptions ($path->[1], $data);
        })->then (sub {
          return $class->send_json ($app, {});
        });
      } else {
        return $db->select ('stream_process', {
          stream_id => Dongry::Type->serialize ('text', $path->[1]),
        })->then (sub {
          my $data = $_[0]->first;
          if (defined $data) {
            return $class->send_json
                ($app, Dongry::Type->parse ('json', $data->{data}));
          } else {
            return $app->send_error (404);
          }
        });
      }
    }
  } # /stream/{stream_id}

  if (@$path == 1 and $path->[0] eq 'run') {
    unless ($app->http->request_method eq 'POST') {
      return $app->send_html (q{
        <!DOCTYPE HTML>
        <title>Run</title>
        <form method=post action=/run target=result>
          <p><button type=submit>Run</button>
        </form>
        <p><iframe name=result style="width:100%;height:30em"></iframe>
      });
    }
    # XXX CSRF

    $app->http->set_response_header
        ('Content-Type', 'text/plain; charset=utf-8');
    my $act = Straw::Action->new_from_db ($db);
    $act->onlog (sub {
      $app->http->send_response_body_as_text ("$_[1]\n");
    });
    return $act->run_fetches->then (sub {
      return $act->run_stream_processes;
    })->then (sub {
      $app->http->close_response_body;
    });
  } # /run

  # XXX is_test and
  if (@$path == 2 and $path->[0] eq 'test' and $path->[1] eq 'queue') {
    # /test/queue
    return $db->execute ('select fetch_key from fetch_task limit 1')->then (sub {
      return $class->send_json ($app, {
        empty => $_[0]->first ? 0 : 1,
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

Copyright 2007-2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
