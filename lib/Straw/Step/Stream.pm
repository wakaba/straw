package Straw::Step::Stream;
use strict;
use warnings;
use Time::HiRes qw(time);
use Digest::SHA qw(sha1_hex);
use JSON::PS;
use Promise;
use Dongry::Type;
use Dongry::Type::JSONPS;

# XXX internal
$Straw::Step->{save_stream} = {
  in_type => 'Stream',
  code => sub {
    my ($self, $step, $in) = @_;
    my $stream_id = $step->{stream_id}; # XXX or error

    ## Stream metadata
    # XXX

    ## Stream items
    return Promise->resolve ($in) unless @{$in->{items}};
    return $self->db->insert ('stream_item', [map {
      my $updated = time;
      my $timestamp = $_->{props}->{timestamp} || $updated;
      my $key = sha1_hex (Dongry::Type->serialize ('text', $_->{props}->{key} // $timestamp));
      +{
        stream_id => Dongry::Type->serialize ('text', $stream_id),
        key => $key,
        data => Dongry::Type->serialize ('json', $_),
        timestamp => $timestamp,
        updated => $updated,
      };
    } reverse @{$in->{items}}], duplicate => 'replace')->then (sub {
      return $in;
    });
  },
}; # save_stream

# XXX internal
$Straw::Step->{load_stream} = {
  in_type => 'Empty',
  code => sub {
    my ($self, $step, $in) = @_;
    my $out = {type => 'Stream', items => []};
    return $self->db->select ('stream_item', {
      stream_id => Dongry::Type->serialize ('text', $step->{stream_id}),
      # XXX paging
    }, order => ['timestamp', 'DESC'])->then (sub {
      for (@{$_[0]->all}) {
        push @{$out->{items}}, Dongry::Type->parse ('json', $_->{data});
      }
    })->then (sub {
      return $out;
    });
  },
}; # load_stream

$Straw::Step->{dump_stream} = {
  in_type => 'Stream',
  code => sub {
    my $in = $_[2];
    $_[0]->onlog->($_[0], perl2json_chars_for_record $in);
    return $in;
  },
}; # dump_stream

$Straw::ItemStep->{use_url_as_key} = sub {
  my $item = $_[0];
  my $v = $item->{props}->{url};
  $item->{props}->{key} = $v if defined $v;
  return $item;
}; # use_url_as_key

$Straw::ItemStep->{select_props} = sub {
  my ($item, $step) = @_;
  my $out = {};
  my @field = (defined $step->{fields} && ref $step->{fields} eq 'ARRAY')
      ? @{$step->{fields} || []} : ();
  for (@field) {
    $out->{props}->{$_} = $item->{props}->{$_}
        if defined $item->{props}->{$_};
  }
  return $out;
}; # select_props

1;
