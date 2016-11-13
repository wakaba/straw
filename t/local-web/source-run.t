use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

Test {
  my $current = shift;
  return $current->remote ({
    q<1> => {text => 'foo'},
  })->then (sub {
    return $current->create_source (s1 => {
      fetch => {url => $current->o ('1')->{url}->stringify},
    });
  })->then (sub {
    return $current->post (['source', $current->o ('s1')->{source_id}, 'enqueue'], {});
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 202;
    } $current->context;
    return $current->wait_drain;
  })->then (sub {
    return $current->client->request (
      path => ['source', $current->o ('s1')->{source_id}, 'fetched'],
      basic_auth => [key => 'test'],
    );
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->header ('Content-Type'), 'message/http';
      is $res->header ('Content-Disposition'), 'attachment';
      is $res->header ('Content-Security-Policy'), 'sandbox';
      ok $res->header ('Last-Modified');
      like $res->content, qr{^HTTP/};
      like $res->content, qr{^foo$}m;
    } $current->context;
  });
} n => 8, name => 'fetch ok';

Test {
  my $current = shift;
  my $key = rand;
  my $after = time;
  return $current->create_source (s1 => {
    fetch => {hoge => $key},
  })->then (sub {
    return $current->post (['source', $current->o ('s1')->{source_id}, 'enqueue'], {});
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 202;
    } $current->context;
    return $current->wait_drain;
  })->then (sub {
    return $current->client->request (
      path => ['source', $current->o ('s1')->{source_id}, 'fetched'],
      basic_auth => [key => 'test'],
    );
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 404;
    } $current->context;
    return $current->get (['source', 'logs'], {after => $after});
  })->then (sub {
    my $result = $_[0];
    test {
      no warnings 'uninitialized';
      is $result->{status}, 200;
      my $items = [grep {
        $_->{error}->{fetch_options}->{hoge} eq $key;
      } @{$result->{json}->{items}}];
      is 0+@$items, 1;
      ok $items->[0]->{fetch_key};
      is $items->[0]->{origin_key}, undef;
      ok $items->[0]->{timestamp};
      ok $items->[0]->{error}->{message};
    } $current->context;
  });
} n => 8, name => 'fetch error';

RUN;

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
