package Straw::Database;
use strict;
use warnings;
use Path::Tiny;
use Dongry::Type;
use Dongry::Type::JSONPS;
use Dongry::Database;

my $config_path = path ($ENV{APP_CONFIG} // die "Bad |APP_CONFIG|");

our $Config = Dongry::Type->parse ('json', $config_path->slurp);
our $Sources = {
  master => {
    dsn => Dongry::Type->serialize ('text', $Config->{alt_dsns}->{master}->{straw}),
    writable => 1, anyevent => 1,
  },
  default => {
    dsn => Dongry::Type->serialize ('text', $Config->{dsns}->{straw}),
    anyevent => 1,
  },
}; # $Sources

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
