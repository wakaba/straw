package Straw::Process;
use strict;
use warnings;

sub new_from_db ($$) {
  return bless {db => $_[1]}, $_[0];
} # new_from_db

sub db ($) {
  return $_[0]->{db};
} # db

sub load_process_by_id ($$) {
  my ($self, $process_id) = @_;
  return $self->db->select ('process', {
    process_id => Dongry::Type->serialize ('text', $process_id),
  })->then (sub {
    my $d = $_[0]->first;
    return undef unless defined $d;
    $d->{process_id} .= '';
    return $d;
  });
} # load_process_by_id

sub save_process ($$) {
  my ($self, $process_options) = @_;
  return Promise->reject ({status => 400, reason => "Bad |process_options|"})
      unless defined $process_options and ref $process_options eq 'HASH';
  my $process_id;
  return $self->db->execute ('select uuid_short() as uuid', undef, source_name => 'master')->then (sub {
    $process_id = $_[0]->first->{uuid};
  })->then (sub {
    return $self->db->insert ('process', [{
      process_id => $process_id,
      process_options => Dongry::Type->serialize ('json', $process_options),
    }], duplicate => 'ignore');

    # XXX subscription
  })->then (sub {
    return ''.$process_id;
  });
} # save_process

1;

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
