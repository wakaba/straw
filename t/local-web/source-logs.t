use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

my $wait = web_server;

test {
  my $c = shift;
  return Promise->resolve->then (sub {
    return GET ($c, qq{/source/logs});
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 200;
      is $res->header ('Content-Type'), 'application/json; charset=utf-8';
      my $json = json_bytes2perl $res->content;
      is ref $json->{items}, 'ARRAY';
      ok defined $json->{next_after};
      ok $json->{next_url};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 5, name => '/source/logs global';

test {
  my $c = shift;
  my $after = time * 2;
  return Promise->resolve->then (sub {
    return GET ($c, qq{/source/logs?after=$after});
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 200;
      is $res->header ('Content-Type'), 'application/json; charset=utf-8';
      my $json = json_bytes2perl $res->content;
      is ref $json->{items}, 'ARRAY';
      is 0+@{$json->{items}}, 0;
      is $json->{next_after}, $after;
      like $json->{next_url}, qr<\Q/source/logs?after=$after\E$>;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 6, name => '/source/logs no more data';

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
