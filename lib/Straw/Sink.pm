package Straw::Sink;
use strict;
use warnings;
use Dongry::Type;
use Promise;

sub new_from_db ($$) {
  return bless {db => $_[1]}, $_[0];
} # new_from_db

sub db ($) {
  return $_[0]->{db};
} # db

sub load_sink_by_id ($$) {
  my ($self, $sink_id) = @_;
  return $self->db->select ('sink', {
    sink_id => Dongry::Type->serialize ('text', $sink_id),
  }, fields => ['sink_id', 'stream_id', 'channel_id'])->then (sub {
    my $d = $_[0]->first;
    return undef unless defined $d;
    $d->{sink_id} .= '';
    $d->{stream_id} .= '';
    return $d;
  });
} # load_sink_by_id

sub save_sink ($$$$) {
  my ($self, $sink_id, $stream_id, $channel_id) = @_;

  return Promise->reject ({status => 400, reason => 'Bad |stream_id|'})
      unless defined $stream_id;
  # XXX validate stream_id

  my $p = Promise->resolve;
  if (defined $sink_id) {
    $p = $p->then (sub {
      return $self->db->select ('sink', {
        sink_id => Dongry::Type->serialize ('text', $sink_id),
      }, fields => ['sink_id'])->then (sub {
        die {status => 404, reason => 'Sink not found'}
            unless $_[0]->first;
      });
    });
  } else {
    $p = $p->then (sub {
      return $self->db->execute ('select uuid_short() as uuid', undef, source_name => 'master');
    })->then (sub {
      $sink_id = $_[0]->first->{uuid};
    });
  }

  return $p->then (sub {
    return $self->db->insert ('sink', [{
      sink_id => Dongry::Type->serialize ('text', $sink_id),
      stream_id => Dongry::Type->serialize ('text', $stream_id),
      channel_id => Dongry::Type->serialize ('text', $channel_id || 0),
    }], duplicate => 'replace');
  })->then (sub {
    return ''.$sink_id;
  });
} # save_sink

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
