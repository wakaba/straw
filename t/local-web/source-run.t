use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

my $wait = web_server;

test {
  my $c = shift;
  my $source;
  return remote ($c, {
    q<1> => 'foo',
  })->then (sub {
    return create_source ($c,
      fetch => {url => $_[0]->{1}},
    );
  })->then (sub {
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
      ok $res->header ('Last-Modified');
      like $res->content, qr{^HTTP/};
      like $res->content, qr{^foo$}m;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 8, name => 'fetch ok';

test {
  my $c = shift;
  my $source;
  my $key = rand;
  my $after = time;
  return Promise->resolve->then (sub {
    return create_source ($c,
      fetch => {hoge => $key},
    );
  })->then (sub {
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
      is $res->code, 404;
    } $c;
    return GET ($c, qq{/source/logs?after=$after});
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 200;
      is $res->header ('Content-Type'), 'application/json; charset=utf-8';
      my $json = json_bytes2perl $res->content;
      my $items = [grep { $_->{error}->{fetch_options}->{hoge} eq $key } @{$json->{items}}];
      is 0+@$items, 1;
      ok $items->[0]->{fetch_key};
      is $items->[0]->{origin_key}, undef;
      ok $items->[0]->{timestamp};
      ok $items->[0]->{error}->{message};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 9, name => 'fetch error';

run_tests;
stop_web_server;

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
