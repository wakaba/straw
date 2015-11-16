package Straw::Web;
use strict;
use warnings;
use Path::Tiny;
use Promise;
use JSON::PS;
use Wanage::HTTP;
use Warabe::App;
use Dongry::Database;
use Dongry::Type;
use Dongry::Type::JSONPS;
use Straw::Action;

my $config_path = path (__FILE__)->parent->parent->parent->child
    ('local/local-server/config/config.json'); # XXX
my $config = json_bytes2perl $config_path->slurp;

sub psgi_app ($) {
  my ($class) = @_;
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

    my $db = Dongry::Database->new
        (sources => {master => {dsn => Dongry::Type->serialize ('text', $config->{alt_dsns}->{master}->{straw}),
                                writable => 1, anyevent => 1},
                     default => {dsn => Dongry::Type->serialize ('text', $config->{dsns}->{straw}),
                                 anyevent => 1}});

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

my $ProcessTimeout = 60; # XXX 60*60;

sub main ($$$) {
  my ($class, $app, $db) = @_;
  my $path = $app->path_segments;

  if (@$path >= 2 and
      $path->[0] eq 'stream' and $path->[1] =~ /\A[0-9]+\z/) {

    if (@$path == 3 and $path->[2] eq 'items') {
      # /stream/{stream_id}/items
      my $act = Straw::Action->new_from_db ($db);
      return $act->steps ($path->[1], {steps => [{name => 'load_stream', stream_id => $path->[1]}], no_save => 1})->then (sub {
        return $class->send_json ($app, $_[0]);
      });
    }

    if (@$path == 3 and $path->[2] eq 'run') {
      # /stream/{stream_id}/run
      return $app->send_error (405)
          unless $app->http->request_method eq 'POST';
      # XXX CSRF
      my $act = Straw::Action->new_from_db ($db);
      return $act->enqueue_stream_processes ([$path->[1]], 0)->then (sub {
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

    use Time::HiRes qw(time);
    my $time = time;
    my $p = Promise->resolve;
    return $db->update ('stream_process_queue', {
      running_since => $time,
    }, where => {
      run_after => {'<=' => $time},
      running_since => 0,
    }, limit => 10, order => ['run_after', 'asc'])->then (sub {
      return $db->select ('stream_process_queue', {
        running_since => $time,
      }, fields => ['stream_id']);
    })->then (sub {
      $app->http->set_response_header
          ('Content-Type', 'text/plain; charset=utf-8');

      my @process_id = map { $_->{stream_id} } @{$_[0]->all};
      return unless @process_id;
      for my $process_id (@process_id) {
        # XXX loop detection
        $p = $p->then (sub {
          $app->http->send_response_body_as_text ("Stream |$process_id|...\n");
          return $db->select ('stream_process', {
            stream_id => Dongry::Type->serialize ('text', $process_id),
          })->then (sub {
            my $data = $_[0]->first;
            unless (defined $data) {
              $app->http->send_response_body_as_text ("Nothing to do\n");
              return;
            }
            my $rule = Dongry::Type->parse ('json', $data->{data});
            my $act = Straw::Action->new_from_db ($db);
            $act->onlog (sub {
              $app->http->send_response_body_as_text ("$_[1]\n");
            });
            return $act->run ($process_id, $rule)->catch (sub {
              $app->http->send_response_body_as_text ("Error: $_[0]\n");
            })->then (sub {
              $app->http->send_response_body_as_text ("Done\n");
            });
          })->then (sub {
            return $db->delete ('stream_process_queue', {
              stream_id => Dongry::Type->serialize ('text', $process_id),
            });
          });
        }); # $p
      } # $process_id
    })->then (sub {
      return $db->delete ('stream_process_queue', {
        running_since => {'<', time - $ProcessTimeout, '!=' => 0},
      })->then (sub {
        return $p;
      })->then (sub {
        $app->http->close_response_body;
      });
    });
  } # /run

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
