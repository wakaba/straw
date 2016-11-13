use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

Test {
  my $current = shift;
  my @result;
  return $current->remote ({
    q<2> => {text => 'foo@@TIME@@'},
    q<2.2> => {text => 'foo'},
  })->then (sub {
    return $current->create_source (s1 => {
      fetch => {url => $current->o ('2.2')->{url}->stringify},
    });
  })->then (sub {
    return $current->post (['source', $current->o ('s1')->{source_id}], {
      fetch_options => perl2json_bytes {url => $current->o ('2')->{url}->stringify},
      schedule_options => perl2json_bytes {every_seconds => 2},
    });
  })->then (sub {
    return promised_wait_until {
      return $current->source_fetched ($current->o ('s1'))->then (sub {
        my $res = $_[0];
        if ($res->content =~ /foo([0-9.]+)$/ and
            (not @result or $result[-1] ne $1)) {
          push @result, $1;
        }
        return @result == 2;
      }, sub { return 0 });
    };
  })->then (sub {
    test {
      ok $result[0] + 2 <= $result[1];
    } $current->context;
  });
} n => 1, name => 'fetch scheduled';

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
