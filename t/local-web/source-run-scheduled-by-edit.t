use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

my $wait = web_server;

test {
  my $c = shift;
  my $source;
  my $url;
  return remote ($c, {
    q<2> => 'foo@@TIME@@',
    q<2.2> => 'foo',
  })->then (sub {
    $url = $_[0]->{2};
    return create_source ($c,
      fetch => {url => $_[0]->{'2.2'}},
    );
  })->then (sub {
    $source = $_[0];
    return POST ($c, qq{/source/$source->{source_id}}, {
      fetch_options => perl2json_bytes {url => $url},
      schedule_options => perl2json_bytes {every_seconds => 2},
    });
  })->then (sub {
    my @result;
    my $try; $try = sub {
      return GET ($c, qq{/source/$source->{source_id}/fetched})->then (sub {
        my $res = $_[0];
        if ($res->code == 200 and $res->content =~ /foo([0-9.]+)$/ and
            (not @result or $result[-1] ne $1)) {
          push @result, $1;
          if (@result == 2) {
            undef $try;
            return;
          }
        }
        return wait_seconds (1)->then ($try);
      });
    }; # $try
    return $try->()->then (sub {
      test {
        ok $result[0] + 2 <= $result[1];
      } $c;
    });
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 1, name => 'fetch scheduled';

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
