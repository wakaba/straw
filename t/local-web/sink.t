use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

my $wait = web_server;

test {
  my $c = shift;
  return GET ($c, q</sink>)->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 405;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/sink GET';

test {
  my $c = shift;
  return POST ($c, q</sink>, {})->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 400;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/sink POST no stream_id';

test {
  my $c = shift;
  return POST ($c, q</sink>, {
    stream_id => 1253333,
  })->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 200;
      ok $json->{sink_id};
      like $res->content, qr{"sink_id"\s*:\s*"};
    } $c;
    return GET ($c, qq{/sink/$json->{sink_id}});
  })->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 200;
      is $json->{sink_id}, $json->{sink_id};
      like $res->content, qr{"sink_id"\s*:\s*"};
      is $json->{stream_id}, 1253333;
      like $res->content, qr{"stream_id"\s*:\s*"};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 8, name => '/sink POST';

test {
  my $c = shift;
  return GET ($c, qq{/sink/532333})->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 404;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/sink/{sink_id} GET not found';

run_tests;
stop_web_server;

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
