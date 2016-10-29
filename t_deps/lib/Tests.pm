package Tests;
use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/modules/*/lib');
use File::Temp;
use AnyEvent;
use Promise;
use Promised::Flow;
use Promised::File;
use Promised::Mysqld;
use Time::HiRes qw(time);
use JSON::PS;
use MIME::Base64;
use Web::UserAgent::Functions qw(http_post http_get);
use Wanage::URL;
use Web::URL;
use Web::Transport::ConnectionClient;
use Test::More;
use Test::X1;
use Sarze;

our @EXPORT;

push @EXPORT, grep { not /^\$/ } @Test::More::EXPORT, @Test::X1::EXPORT, @JSON::PS::EXPORT, 'time';

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

{
  use Socket;
  my $EphemeralStart = 1024;
  my $EphemeralEnd = 5000;

  sub is_listenable_port ($) {
    my $port = $_[0];
    return 0 unless $port;
    
    my $proto = getprotobyname('tcp');
    socket(my $server, PF_INET, SOCK_STREAM, $proto) || die "socket: $!";
    setsockopt($server, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) || die "setsockopt: $!";
    bind($server, sockaddr_in($port, INADDR_ANY)) || return 0;
    listen($server, SOMAXCONN) || return 0;
    close($server);
    return 1;
  } # is_listenable_port

  my $using = {};
  sub find_listenable_port () {
    for (1..10000) {
      my $port = int rand($EphemeralEnd - $EphemeralStart);
      next if $using->{$port}++;
      return $port if is_listenable_port $port;
    }
    die "Listenable port not found";
  } # find_listenable_port
}

push @EXPORT, qw(origin_of);
sub origin_of ($) {
  return Wanage::URL->new_from_string ($_[0] // '')->ascii_origin; # or undef
} # origin_of

{
my $RemoteHostport;
sub remote_server () {
  my $port = find_listenable_port;
  return Sarze->start (
    hostports => [['127.0.0.1', $port]],
    max_worker_count => 1,
    eval => q{
    use strict;
    use warnings;
    use Wanage::HTTP;
    use Warabe::App;
    use MIME::Base64;
    use JSON::PS;
    use Time::HiRes qw(time);

    my $Data = {};

    sub psgi_app {
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

        return $app->send_error (404, reason_phrase => 'URL not registered');
      });
    };
    },
  )->then (sub {
    $RemoteServer = $_[0];
    $RemoteHostport = "localhost:$port";
  });
} # remote_server

sub remote_url ($) {
  return qq<http://$RemoteHostport$_[0]>;
} # remote_url
}

push @EXPORT, qw(web_server);
sub web_server (;@) {
  my %args = @_;
  my $bearer = rand;
  $MySQLServer = Promised::Mysqld->new;
  my $http_port = find_listenable_port;
  my $url = Web::URL->parse_string ("http://localhost:$http_port");
  return Promise->all ([
    $MySQLServer->start,
    remote_server,
  ])->then (sub {
    my $dsn = $MySQLServer->get_dsn_string (dbname => 'straw_test');
    $MySQLServer->{_temp} = my $temp = File::Temp->newdir;
    my $temp_dir_path = path ($temp)->absolute;
    my $temp_path = $temp_dir_path->child ('file');
    my $temp_file = Promised::File->new_from_path ($temp_path);

    $HTTPServer = Promised::Command->new
        ([$root_path->child ('perl'),
          $root_path->child ('bin/sarze-server.pl'),
          $http_port]);
    $HTTPServer->propagate_signal (1);
    $HTTPServer->envs->{APP_CONFIG} = $temp_path;
    $HTTPServer->envs->{STRAW_WORKER_INTERVAL} = $args{worker_interval} || 5;
    $HTTPServer->envs->{http_proxy} = remote_url q<>;
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
        api_key => 'test',
      }),
    ]);
  })->then (sub {
    return $HTTPServer->run;
  })->then (sub {
    my $client = Web::Transport::ConnectionClient->new_from_url ($url);
    return promised_wait_until {
      return promised_timeout {
        return $client->request (path => ['ping'])->then (sub {
          return not $_[0]->is_network_error;
        }, sub { return 0 });
      } 10;
    } interval => 0.3;
  })->then (sub {
    return {host => $url->hostport};
  })->to_cv;
} # web_server

push @EXPORT, qw(stop_web_server);
sub stop_web_server () {
  (promised_cleanup {
    undef $HTTPServer;
    undef $MySQLServer;
    undef $RemoteServer;
  } Promise->all ([
    do {
      if (defined $HTTPServer) {
        $HTTPServer->send_signal ('TERM');
        $HTTPServer->wait;
      }
    },
    (defined $MySQLServer ? $MySQLServer->stop : undef),
    (defined $RemoteServer ? $RemoteServer->stop : undef),
  ]))->to_cv->recv;
} # stop_web_server

push @EXPORT, qw(GET);
sub GET ($$) {
  my ($c, $url) = @_;
  my $host = $c->received_data->{host};
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    http_get
        url => qq{http://$host$url},
        basic_auth => [key => 'test'],
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
        basic_auth => [key => 'test'],
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
  my @origin;
  for (ref $input eq 'ARRAY' ? @$input : $input) {
    if (defined $_->{source_id}) {
      push @source_id, $_->{source_id};
    } elsif (defined $_->{stream_id}) {
      push @stream_id, $_->{stream_id};
    } elsif (defined $_->{origin}) {
      push @origin, $_->{origin};
    } else {
      die "Bad input: |$_|";
    }
  }
  return POST ($c, q</process>, {
    process_options => perl2json_chars {
      (@source_id ? (input_source_ids => \@source_id) : ()),
      (@origin ? (input_origins => \@origin) : ()),
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

push @EXPORT, qw(remote);
sub remote ($$) {
  my ($c, $eps) = @_;
  my $p = Promise->resolve;
  my $dir_path = q</> . rand . q</>;
  my $origin_prefix = q<http://test> . rand;
  my $result = {};
  for my $key (keys %$eps) {
    my $path = $dir_path . $key;
    my $headers = {};
    my $body = $eps->{$key};
    my $opts = {};
    if (defined $body and ref $body eq 'ARRAY') {
      ($headers, $body, $opts) = @$body;
    }
    my $origin =remote_url '';
    if (defined $opts->{origin}) {
      $origin = qq{$origin_prefix.$opts->{origin}};
    }
    $p = $p->then (sub {
      $body =~ s{\@\@URL\{([^{}]*)\}\@\@}{$result->{$1}}g;
      return Promise->new (sub {
        my ($ok, $ng) = @_;
        http_post
            url => remote_url $path,
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
    $result->{$key} = qq<$origin$path>;
  }
  return $p->then (sub { return $result });
} # remote

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
