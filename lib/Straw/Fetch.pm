package Straw::Fetch;
use strict;
use warnings;
use Digest::SHA qw(sha1_hex);
use JSON::PS;
use Dongry::Type;
use Dongry::Type::JSONPS;
use Promise;

sub new_from_db ($$) {
  return bless {db => $_[1]}, $_[0];
} # new_from_db

sub db ($) {
  return $_[0]->{db};
} # db

sub load_fetch_source_by_id ($$) {
  my ($self, $source_id) = @_;
  return $self->db->select ('fetch_source', {
    source_id => Dongry::Type->serialize ('text', $source_id),
  })->then (sub {
    my $data = $_[0]->first;
    return undef unless defined $data;
    $data->{source_id} .= '';
    return $data;
  });
} # load_fetch_source_by_id

sub save_fetch_source ($$$$) {
  my ($self, $source_id, $fetch_options, $schedule_options) = @_;
  return Promise->reject ({status => 400, reason => "Bad |fetch_options|"})
      unless defined $fetch_options and ref $fetch_options eq 'HASH';
  return Promise->reject ({status => 400, reason => "Bad |schedule_options|"})
      unless defined $schedule_options and ref $schedule_options eq 'HASH';
  my $url = Dongry::Type->serialize ('text', $fetch_options->{url} // '');
  $fetch_options = perl2json_bytes_for_record $fetch_options;
  my $fetch_key = sha1_hex $url;
  $fetch_key .= sha1_hex $fetch_options;
  my $p = Promise->resolve;
  if (defined $source_id) {
    $p = $p->then (sub {
      return $self->db->select ('fetch_source', {
        source_id => Dongry::Type->serialize ('text', $source_id),
      }, fields => ['source_id'])->then (sub {
        die {status => 404, reason => 'Fetch source not found'}
            unless $_[0]->first;
      });
    });
  } else {
    $p = $p->then (sub {
      return $self->db->execute ('select uuid_short() as uuid', undef, source_name => 'master')->then (sub {
        $source_id = $_[0]->first->{uuid};
      });
    });
  }
  return $p->then (sub {
    return $self->db->insert ('fetch_source', [{
      source_id => Dongry::Type->serialize ('text', $source_id),
      fetch_key => $fetch_key,
      fetch_options => $fetch_options,
      schedule_options => Dongry::Type->serialize ('json', $schedule_options),
    }], duplicate => 'replace');
  })->then (sub {
    return ''.$source_id;
  });
} # save_fetch_source

1;
