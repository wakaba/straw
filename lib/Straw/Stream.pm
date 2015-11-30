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

1;
