package Straw::Web;
use strict;
use warnings;
use Path::Tiny;
use Promise;
use JSON::PS;
use Wanage::HTTP;
use Warabe::App;
use Dongry::Database;
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
        return $db->disconnect->then (sub { return $e }, sub { return $e });
      });
    });
  };
} # psgi_app

sub main ($$$) {
  my ($class, $app, $db) = @_;
  my $path = $app->path_segments;

  if (@$path == 2 and
      $path->[0] eq 'stream' and $path->[1] =~ /\A[0-9]+\z/) {
    # /stream/{stream_id}
    my $act = Straw::Action->new_from_db ($db);
    return $act->load_stream ({type => 'streamref', stream_id => $path->[1]})->then (sub {
      $app->http->set_response_header
          ('Content-Type' => 'application/json; charset=utf-8');
      $app->http->send_response_body_as_text
          (perl2json_chars_for_record $_[0]);
      $app->http->close_response_body;
    });
  }

  return $app->send_error (404);
} # main

1;

=head1 LICENSE

Copyright 2007-2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
