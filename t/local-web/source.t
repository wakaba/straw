use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

my $wait = web_server;

test {
  my $c = shift;
  return GET ($c, q</source>)->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 405;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/source GET';

test {
  my $c = shift;
  return POST ($c, q</source>, {})->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 400;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/source POST';

test {
  my $c = shift;
  return POST ($c, q</source>, {type => 'hoge'})->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 400;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/source POST bad type';

test {
  my $c = shift;
  return POST ($c, q</source>, {
    type => 'fetch_source',
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 400;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/source POST fetch_source no options';

test {
  my $c = shift;
  return POST ($c, q</source>, {
    type => 'fetch_source',
    fetch_options => '[]',
    schedule_options => '[]',
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 400;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/source POST fetch_source bad options';

test {
  my $c = shift;
  return POST ($c, q</source>, {
    type => 'fetch_source',
    fetch_options => '{"a":1}',
    schedule_options => '{"b":2}',
  })->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 200;
      ok $json->{source_id};
      like $res->content, qr{"source_id"\s*:\s*"};
    } $c;
    return GET ($c, qq{/source/$json->{source_id}});
  })->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 200;
      is $json->{type}, 'fetch_source';
      like $json->{fetch}->{fetch_key}, qr{^[0-9a-f]{80}$};
      is $json->{fetch}->{fetch_options}->{a}, 1;
      is $json->{fetch}->{schedule_options}->{b}, 2;
      is $json->{source_id}, $json->{source_id};
      like $res->content, qr{"source_id"\s*:\s*"};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 10, name => '/source POST fetch_source';

test {
  my $c = shift;
  return GET ($c, qq{/source/532333})->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 404;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/source/{source_id} GET not found';

test {
  my $c = shift;
  return POST ($c, qq{/source/532333}, {
    fetch_options => perl2json_bytes {c => 55},
    schedule_options => perl2json_bytes {d => 51},
  })->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 404;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => '/source/{source_id} POST not found';

test {
  my $c = shift;
  return create_source ($c,
    fetch => {a => 5},
    schedule => {b => 1},
  )->then (sub {
    my $source = $_[0];
    return GET ($c, qq{/source/$source->{source_id}});
  })->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 200;
      is $json->{type}, 'fetch_source';
      like $json->{fetch}->{fetch_key}, qr{^[0-9a-f]{80}$};
      is $json->{fetch}->{fetch_options}->{a}, 5;
      is $json->{fetch}->{schedule_options}->{b}, 1;
      is $json->{source_id}, $json->{source_id};
      like $res->content, qr{"source_id"\s*:\s*"};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 7, name => '/source/{source_id} GET';

test {
  my $c = shift;
  my $source;
  return create_source ($c,
    fetch => {a => 5},
    schedule => {b => 1},
  )->then (sub {
    $source = $_[0];
    return POST ($c, qq{/source/$source->{source_id}}, {
      fetch_options => perl2json_bytes {c => 55},
      schedule_options => perl2json_bytes {d => 51},
    });
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 200;
    } $c;
    return POST ($c, qq{/source/$source->{source_id}}, {
      fetch_options => perl2json_bytes {c => 55},
      schedule_options => undef,
    });
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 400;
    } $c;
    return GET ($c, qq{/source/$source->{source_id}});
  })->then (sub {
    my $res = $_[0];
    my $json = json_bytes2perl $res->content;
    test {
      is $res->code, 200;
      is $json->{type}, 'fetch_source';
      like $json->{fetch}->{fetch_key}, qr{^[0-9a-f]{80}$};
      is $json->{fetch}->{fetch_options}->{a}, undef;
      is $json->{fetch}->{fetch_options}->{c}, 55;
      is $json->{fetch}->{schedule_options}->{b}, undef;
      is $json->{fetch}->{schedule_options}->{d}, 51;
      is $json->{source_id}, $json->{source_id};
      like $res->content, qr{"source_id"\s*:\s*"};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 11, name => '/source/{source_id} GET';

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
