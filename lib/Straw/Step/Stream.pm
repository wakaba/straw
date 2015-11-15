package Straw::Step::Stream;
use strict;
use warnings;
use JSON::PS;
use Promise;
use Dongry::Type;
use Dongry::Type::JSONPS;

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
      my $key = undef;
      my $time = time;
      $key //= $time;
      +{
        stream_id => Dongry::Type->serialize ('text', $stream_id),
        item_key => $key, # XXX
        data => Dongry::Type->serialize ('json', $_),
        stream_item_timestamp => $time,
      };
    } reverse @{$in->{items}}], duplicate => 'replace')->then (sub { return $in });
  },
}; # save_stream

$Straw::Step->{dump_stream} = {
  in_type => 'Stream',
  code => sub {
    my $in = $_[2];
    $_[0]->onlog->($_[0], perl2json_chars_for_record $in);
    return $in;
  },
}; # dump_stream

1;
