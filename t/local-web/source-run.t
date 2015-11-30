use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

my $wait = web_server;

test {
  my $c = shift;
  my $source;
  return create_source ($c,
    fetch => {url => remote_url q</1>},
  )->then (sub {
    $source = $_[0];
    return POST ($c, qq{/source/$source->{source_id}/enqueue}, {});
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 202;
    } $c;
    return wait_drain $c;
  })->then (sub {
    return GET ($c, qq{/source/$source->{source_id}/fetched});
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 200;
      is $res->header ('Content-Type'), 'message/http';
      is $res->header ('Content-Disposition'), 'attachment';
      is $res->header ('Content-Security-Policy'), 'sandbox';
      like $res->content, qr{text/plain};
      like $res->content, qr{^foo$}m;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 7, name => 'fetch ok';

run_tests;
stop_web_server;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
