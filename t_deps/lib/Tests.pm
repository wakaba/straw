package Tests;
use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/modules/*/lib');
use File::Temp;
use AnyEvent;
use Promise;
use Promised::File;
use Promised::Plackup;
use Promised::Mysqld;
use JSON::PS;
use MIME::Base64;
use Web::UserAgent::Functions qw(http_post http_get);
use Test::More;
use Test::X1;

our @EXPORT;

push @EXPORT, grep { not /^\$/ } @Test::More::EXPORT, @Test::X1::EXPORT, @JSON::PS::EXPORT;

sub import ($;@) {
  my $from_class = shift;
  my ($to_class, $file, $line) = caller;
  no strict 'refs';
  for (@_ ? @_ : @{$from_class . '::EXPORT'}) {
    my $code = $from_class->can ($_)
        or die qq{"$_" is not exported by the $from_class module at $file line $line};
    *{$to_class . '::' . $_} = $code;
  }
} # import

my $MySQLServer;
my $HTTPServer;
my $RemoteServer;

my $root_path = path (__FILE__)->parent->parent->parent->absolute;

sub remote_server (;$) {
  my $web_host = $_[0];
  my $cv = AE::cv;
  $RemoteServer = Promised::Plackup->new;
  $RemoteServer->set_option ('--server' => 'Twiggy');
  $RemoteServer->plackup ($root_path->child ('plackup'));
  $RemoteServer->set_option ('--host' => $web_host) if defined $web_host;
  $RemoteServer->set_option ('-e' => q{
    use strict;
    use warnings;
    use Wanage::HTTP;
    use Warabe::App;
    use MIME::Base64;
    use JSON::PS;
    use Time::HiRes qw(time);

    my $Data = {};

    return sub {
      my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
      my $app = Warabe::App->new_from_http ($http);
      return $app->execute_by_promise (sub {
        my $path = $app->http->url->{path};

        if ($app->http->request_method eq 'POST') {
          $Data->{$path} = {
            headers => json_bytes2perl ($app->bare_param ('headers') // ''),
            body => decode_base64 ($app->bare_param ('body') // ''),
          };
          return $app->send_error (200);
        } else {
          my $data = $Data->{$path};
          if (defined $data) {
            if (defined $data->{headers} and ref $data->{headers} eq 'HASH') {
              for (keys %{$data->{headers}}) {
                $app->http->set_response_header ($_ => $data->{headers}->{$_});
              }
            }
            my $body = $data->{body};
            $body =~ s/\@\@TIME\@\@/time/ge;
            $app->http->send_response_body_as_ref (\$body);
            return $app->http->close_response_body;
          }
        }

        return $app->send_error (404);
      });
    };
  });
  return $RemoteServer;
} # remote_server

push @EXPORT, qw(web_server);
sub web_server (;$) {
  my $web_host = $_[0];
  my $cv = AE::cv;
  my $bearer = rand;
  $MySQLServer = Promised::Mysqld->new;
  remote_server;
  Promise->all ([
    $MySQLServer->start,
    $RemoteServer->start,
  ])->then (sub {
    my $dsn = $MySQLServer->get_dsn_string (dbname => 'straw_test');
    $MySQLServer->{_temp} = my $temp = File::Temp->newdir;
    my $temp_dir_path = path ($temp)->absolute;
    my $temp_path = $temp_dir_path->child ('file');
    my $temp_file = Promised::File->new_from_path ($temp_path);
    $HTTPServer = Promised::Plackup->new;
    $HTTPServer->set_option ('--server' => 'Twiggy');
    $HTTPServer->envs->{APP_CONFIG} = $temp_path;
    return Promise->all ([
      Promised::File->new_from_path ($root_path->child ('db/straw.sql'))->read_byte_string->then (sub {
        return [grep { length } split /;/, $_[0]];
      })->then (sub {
        $MySQLServer->create_db_and_execute_sqls (straw_test => $_[0]);
      }),
      Promised::File->new_from_path ($root_path->child ('db/straw-procedures.sql'))->read_byte_string->then (sub {
        return [grep { length } split /^\@\@\@\@$/m, $_[0]];
      })->then (sub {
        $MySQLServer->create_db_and_execute_sqls (straw_test => $_[0]);
      }),
      $temp_file->write_byte_string (perl2json_bytes +{
        alt_dsns => {master => {straw => $dsn}},
        dsns => {straw => $dsn},
      }),
    ]);
  })->then (sub {
    $HTTPServer->plackup ($root_path->child ('plackup'));
    $HTTPServer->set_option ('--host' => $web_host) if defined $web_host;
    $HTTPServer->set_option ('--app' => $root_path->child ('bin/server.psgi'));
    return $HTTPServer->start;
  })->then (sub {
    $cv->send ({host => $HTTPServer->get_host});
  });
  return $cv;
} # web_server

push @EXPORT, qw(stop_web_server);
sub stop_web_server () {
  my $cv = AE::cv;
  $cv->begin;
  for ($HTTPServer, $MySQLServer, $RemoteServer) {
    next unless defined $_;
    $cv->begin;
    $_->stop->then (sub { $cv->end });
  }
  $cv->end;
  $cv->recv;
} # stop_web_server

push @EXPORT, qw(GET);
sub GET ($$) {
  my ($c, $url) = @_;
  my $host = $c->received_data->{host};
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    http_get
        url => qq{http://$host$url},
        timeout => 60,
        anyevent => 1,
        cb => sub {
          my (undef, $res) = @_;
          $ok->($res);
        };
  });
} # GET

push @EXPORT, qw(POST);
sub POST ($$$) {
  my ($c, $url, $params) = @_;
  my $host = $c->received_data->{host};
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    http_post
        url => qq{http://$host$url},
        params => $params,
        timeout => 60,
        anyevent => 1,
        cb => sub {
          my (undef, $res) = @_;
          $ok->($res);
        };
  });
} # POST

push @EXPORT, qw(create_source);
sub create_source ($%) {
  my ($c, %args) = @_;
  $args{type} //= 'fetch_source' if defined $args{fetch};
  return POST ($c, q</source>, {
    type => $args{type},
    fetch_options => (perl2json_bytes $args{fetch}),
    schedule_options => (perl2json_bytes ($args{schedule} || {})),
  })->then (sub {
    my $res = $_[0];
    die "create_source failed" unless $res->code == 200;
    return json_bytes2perl $res->content;
  });
} # create_source

push @EXPORT, qw(enqueue_task);
sub enqueue_task ($$) {
  my ($c, $source) = @_;
  return POST ($c, qq{/source/$source->{source_id}/enqueue}, {})->then (sub {
    die $_[0]->as_string unless $_[0]->code == 202;
  });
} # enqueue_task

push @EXPORT, qw(create_sink);
sub create_sink ($$;%) {
  my ($c, $stream, %args) = @_;
  return POST ($c, q</sink>, {
    stream_id => $stream->{stream_id},
    channel_id => $args{channel_id} || 0,
  })->then (sub {
    die $_[0]->as_string unless $_[0]->code == 200;
    return json_bytes2perl $_[0]->content;
  });
} # create_sink

push @EXPORT, qw(create_stream);
sub create_stream ($) {
  my ($c) = @_;
  return POST ($c, q</stream>, {})->then (sub {
    die $_[0]->as_string unless $_[0]->code == 200;
    return json_bytes2perl $_[0]->content;
  });
} # create_stream

push @EXPORT, qw(create_process);
sub create_process ($$$$;%) {
  my ($c, $input => $steps => $output, %args) = @_;
  my @source_id;
  my @stream_id;
  for (ref $input eq 'ARRAY' ? @$input : $input) {
    if (defined $_->{source_id}) {
      push @source_id, $_->{source_id};
    } elsif (defined $_->{stream_id}) {
      push @stream_id, $_->{stream_id};
    } else {
      die "Bad input: |$_|";
    }
  }
  return POST ($c, q</process>, {
    process_options => perl2json_chars {
      (@source_id ? (input_source_ids => \@source_id) : ()),
      (@stream_id ? (input_stream_ids => \@stream_id) : ()),
      input_channel_mappings => $args{channel_map},
      steps => $steps,
      output_stream_id => $output->{stream_id},
    },
  })->then (sub {
    die $_[0]->as_string unless $_[0]->code == 200;
    return json_bytes2perl $_[0]->content;
  });
} # create_process

push @EXPORT, qw(wait_seconds);
sub wait_seconds ($) {
  my $seconds = $_[0];
  return Promise->new (sub {
    my $ok = $_[0];
    my $timer; $timer = AE::timer $seconds, 0, sub {
      $ok->();
      undef $timer;
    };
  });
} # wait_seconds

push @EXPORT, qw(wait_drain);
sub wait_drain ($) {
  my $c = $_[0];
  my $check = sub {
    return POST ($c, q</test/queue>, {})->then (sub {
      my $json = json_bytes2perl $_[0]->content;
      return $json->{empty};
    });
  }; # $check

  my $try; $try = sub {
    return $check->()->then (sub {
      return wait_seconds (1)->then ($try) unless $_[0];
    });
  }; # $try
  return $try->()->then (sub { undef $try });
} # wait_drain

sub remote_url ($) {
  my $host = $RemoteServer->get_host;
  return qq<http://$host$_[0]>;
} # remote_url

push @EXPORT, qw(remote);
sub remote ($$) {
  my ($c, $eps) = @_;
  my $p = Promise->resolve;
  my $host = $RemoteServer->get_host;
  my $dir_path = q</> . rand . q</>;
  my $result = {};
  for my $key (keys %$eps) {
    my $path = $dir_path . $key;
    my $headers = {};
    my $body = $eps->{$key};
    if (defined $body and ref $body eq 'ARRAY') {
      $headers = $body->[0];
      $body = $body->[1];
    }
    $body =~ s{\@\@URLDIR\@\@}{http://$host$dir_path}g;
    $p = $p->then (sub {
      return Promise->new (sub {
        my ($ok, $ng) = @_;
        http_post
            url => qq{http://$host$path},
            params => {headers => (perl2json_chars $headers),
                       body => (encode_base64 $body)},
            timeout => 60,
            anyevent => 1,
            cb => sub {
              my (undef, $res) = @_;
              $ok->($res);
            };
      });
    });
    $result->{$key} = qq<http://$host$path>;
  }
  return $p->then (sub { return $result });
} # remote

1;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

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
