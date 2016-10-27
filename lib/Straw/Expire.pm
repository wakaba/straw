package Straw::Expire;
use strict;
use warnings;
use Time::HiRes qw(time);
use Promise;

my $ExpirationWorkerSleep = 10*60;
my $FetchTimeout = 60*5;
my $ProcessTimeout = 60*60;
my $ErrorLogTimeout = 60*60;
my $StreamItemTimeout = 60*60*24*10;

sub run ($$) {
  my (undef, $db) = @_;
  my $now = time;
  return Promise->resolve->then (sub {
    return $db->update ('process_task', {running_since => 0}, where => {
      running_since => {'<', $now - $ProcessTimeout, '!=' => 0},
    });
  })->then (sub {
    return $db->update ('fetch_task', {running_since => 0}, where => {
      running_since => {'<', $now - $FetchTimeout, '!=' => 0},
    });
  })->then (sub {
    return $db->delete ('fetch_result', {
      expires => {'<', $now},
    });
  })->then (sub {
    return $db->delete ('fetch_error', {
      timestamp => {'<', $now - $ErrorLogTimeout},
    });
  })->then (sub {
    return $db->delete ('process_error', {
      timestamp => {'<', $now - $ErrorLogTimeout},
    });
  })->then (sub {
    return $db->delete ('stream_item_data', {
      updated => {'<', $now - $StreamItemTimeout},
    });
  })
} # run

1;

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
