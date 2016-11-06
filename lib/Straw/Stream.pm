package Straw::Stream;
use strict;
use warnings;
use Dongry::Type;

sub new_from_db ($$) {
  return bless {db => $_[1]}, $_[0];
} # new_from_db

sub db ($) {
  return $_[0]->{db};
} # db

sub load_stream_by_id ($$) {
  my ($self, $stream_id) = @_;
  return $self->db->select ('stream', {
    stream_id => Dongry::Type->serialize ('text', $stream_id),
  })->then (sub {
    my $d = $_[0]->first;
    return undef unless defined $d;
    $d->{stream_id} .= '';
    return $d;
  });
} # load_stream_by_id

sub save_stream ($) {
  my ($self) = @_;
  my $stream_id;
  return $self->db->execute ('select uuid_short() as uuid', undef, source_name => 'master')->then (sub {
    $stream_id = $_[0]->first->{uuid};
  })->then (sub {
    return $self->db->insert ('stream', [{
      stream_id => $stream_id,
    }], duplicate => 'ignore');
  })->then (sub {
    return ''.$stream_id;
  });
} # save_stream

sub load_item_data ($%) {
  my ($self, %args) = @_;
  my $after = 0+($args{after} || 0);
  return $self->db->select ('stream_item_data', {
    stream_id => Dongry::Type->serialize ('text', $args{stream_id}),
    channel_id => Dongry::Type->serialize ('text', $args{channel_id}),
    updated => {'>', $after},
  }, fields => ['data', 'updated', 'item_key'], order => ['updated', 'asc'], limit => 100)->then (sub {
    my $items = [map {
      {
        data => Dongry::Type->parse ('json', $_->{data})->{props},
        timestamp => $_->{updated},
        item_key => $_->{item_key},
      };
    } @{$_[0]->all}];
    my $next_after = @$items ? $items->[-1]->{timestamp} : $after;
    return {items => $items, next_after => $next_after};
  });
} # load_item_data

sub reset_stream_subscription ($$) {
  my ($self, $stream_id) = @_;
  return $self->db->update ('stream_subscription', {
    last_updated => 0,
  }, where => {
    stream_id => Dongry::Type->serialize ('text', $stream_id),
  });
} # reset_stream_subscription

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
