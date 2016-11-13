use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

Test {
  my $current = shift;
  return $current->get (['source'])->catch (sub {
    my $res = $_[0];
    test {
      is $res->code, 405;
    } $current->context;
  });
} n => 1, name => '/source GET';

Test {
  my $current = shift;
  return $current->post (['source'], {})->catch (sub {
    my $res = $_[0];
    test {
      is $res->status, 400;
    } $current->context;
  });
} n => 1, name => '/source POST';

Test {
  my $current = shift;
  return $current->post (['source'], {type => 'hoge'})->catch (sub {
    my $res = $_[0];
    test {
      is $res->code, 400;
    } $current->context;
  });
} n => 1, name => '/source POST bad type';

Test {
  my $current = shift;
  return $current->post (['source'], {
    type => 'fetch_source',
  })->catch (sub {
    my $res = $_[0];
    test {
      is $res->code, 400;
    } $current->context;
  });
} n => 1, name => '/source POST fetch_source no options';

Test {
  my $current = shift;
  return $current->post (['source'], {
    type => 'fetch_source',
    fetch_options => '[]',
    schedule_options => '[]',
  })->catch (sub {
    my $res = $_[0];
    test {
      is $res->code, 400;
    } $current->context;
  });
} n => 1, name => '/source POST fetch_source bad options';

Test {
  my $current = shift;
  return $current->post (['source'], {
    type => 'fetch_source',
    fetch_options => '{"a":1}',
    schedule_options => '{"b":2}',
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      ok $result->{json}->{source_id};
      like $result->{res}->content, qr{"source_id"\s*:\s*"};
    } $current->context;
    return $current->get (['source', $result->{json}->{source_id}]);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      is $result->{json}->{type}, 'fetch_source';
      like $result->{json}->{fetch}->{fetch_key}, qr{^[0-9a-f]{80}$};
      is $result->{json}->{fetch}->{fetch_options}->{a}, 1;
      is $result->{json}->{fetch}->{schedule_options}->{b}, 2;
      is $result->{json}->{source_id}, $result->{json}->{source_id};
      like $result->{res}->content, qr{"source_id"\s*:\s*"};
    } $current->context;
  });
} n => 10, name => '/source POST fetch_source';

Test {
  my $current = shift;
  return $current->get (['source', '532333'])->catch (sub {
    my $res = $_[0];
    test {
      is $res->status, 404;
    } $current->context;
  });
} n => 1, name => '/source/{source_id} GET not found';

Test {
  my $current = shift;
  return $current->post (['source', '532333'], {
    fetch_options => perl2json_bytes {c => 55},
    schedule_options => perl2json_bytes {d => 51},
  })->catch (sub {
    my $res = $_[0];
    test {
      is $res->status, 404;
    } $current->context;
  });
} n => 1, name => '/source/{source_id} POST not found';

Test {
  my $current = shift;
  return $current->create_source (s1 => {
    fetch => {a => 5},
    schedule => {b => 1},
  })->then (sub {
    return $current->get (['source', $current->o ('s1')->{source_id}]);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      my $json = $result->{json};
      is $json->{type}, 'fetch_source';
      like $json->{fetch}->{fetch_key}, qr{^[0-9a-f]{80}$};
      is $json->{fetch}->{fetch_options}->{a}, 5;
      is $json->{fetch}->{schedule_options}->{b}, 1;
      is $json->{source_id}, $json->{source_id};
      like $result->{res}->content, qr{"source_id"\s*:\s*"};
    } $current->context;
  });
} n => 7, name => '/source/{source_id} GET';

Test {
  my $current = shift;
  return $current->create_source (s1 => {
    fetch => {a => 5},
    schedule => {b => 1},
  })->then (sub {
    return $current->post (['source', $current->o ('s1')->{source_id}], {
      fetch_options => perl2json_bytes {c => 55},
      schedule_options => perl2json_bytes {d => 51},
    });
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
    } $current->context;
    return $current->post (['source', $current->o ('s1')->{source_id}], {
      fetch_options => perl2json_bytes {c => 55},
      schedule_options => undef,
    });
  })->catch (sub {
    my $res = $_[0];
    test {
      is $res->status, 400;
    } $current->context;
    return $current->get (['source', $current->o ('s1')->{source_id}]);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      my $json = $result->{json};
      is $json->{type}, 'fetch_source';
      like $json->{fetch}->{fetch_key}, qr{^[0-9a-f]{80}$};
      is $json->{fetch}->{origin_key}, undef;
      is $json->{fetch}->{fetch_options}->{a}, undef;
      is $json->{fetch}->{fetch_options}->{c}, 55;
      is $json->{fetch}->{schedule_options}->{b}, undef;
      is $json->{fetch}->{schedule_options}->{d}, 51;
      is $json->{source_id}, $json->{source_id};
      like $result->{res}->content, qr{"source_id"\s*:\s*"};
    } $current->context;
  });
} n => 12, name => '/source/{source_id} GET';

Test {
  my $current = shift;
  return $current->post (['source'], {
    type => 'fetch_source',
    fetch_options => '{"url":"https://hoge.test/foo/bar"}',
    schedule_options => '{"b":2}',
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      ok $result->{json}->{source_id};
      like $result->{res}->content, qr{"source_id"\s*:\s*"};
    } $current->context;
    return $current->get (['source', $result->{json}->{source_id}]);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      my $json = $result->{json};
      is $json->{type}, 'fetch_source';
      like $json->{fetch}->{fetch_key}, qr{^[0-9a-f]{80}$};
      like $json->{fetch}->{origin_key}, qr{^[0-9a-f]{40}$};
      is $json->{fetch}->{schedule_options}->{b}, 2;
      is $json->{source_id}, $json->{source_id};
      like $result->{res}->content, qr{"source_id"\s*:\s*"};
    } $current->context;
  });
} n => 10, name => '/source POST fetch_source with origin_key';

Test {
  my $current = shift;
  return $current->post (['source'], {
    type => 'fetch_source',
    fetch_options => '{"url":"about:hoge.test/foo/bar"}',
    schedule_options => '{"b":2}',
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      ok $result->{json}->{source_id};
      like $result->{res}->content, qr{"source_id"\s*:\s*"};
    } $current->context;
    return $current->get (['source', $result->{json}->{source_id}]);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      my $json = $result->{json};
      is $json->{type}, 'fetch_source';
      like $json->{fetch}->{fetch_key}, qr{^[0-9a-f]{80}$};
      is $json->{fetch}->{origin_key}, undef;
      is $json->{fetch}->{schedule_options}->{b}, 2;
      is $json->{source_id}, $json->{source_id};
      like $result->{res}->body_bytes, qr{"source_id"\s*:\s*"};
    } $current->context;
  });
} n => 10, name => '/source POST fetch_source with no origin_key';

RUN;

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
