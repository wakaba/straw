use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

my $wait = web_server;

test {
  my $c = shift;
  return GET ($c, q</stream>)->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 405;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/stream GET';

test {
  my $c = shift;
  return POST ($c, q</stream>, {})->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 200;
      ok $json->{stream_id};
      like $res->content, qr{"stream_id"\s*:\s*"};
    } $c;
    return GET ($c, qq{/stream/$json->{stream_id}});
  })->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 200;
      is $json->{stream_id}, $json->{stream_id};
      like $res->content, qr{"stream_id"\s*:\s*"};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 6, name => '/stream POST fetch_source';

test {
  my $c = shift;
  return GET ($c, qq{/stream/532333})->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 404;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/stream/{source_id} GET not found';

run_tests;
stop_web_server;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
