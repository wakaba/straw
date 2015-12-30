package Straw::Step::Stream;
use strict;
use warnings;
use Time::HiRes qw(time);
use Digest::SHA qw(sha1_hex);
use JSON::PS;
use Promise;
use Dongry::Type;
use Dongry::Type::JSONPS;

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
  my $v = $item->{0}->{props}->{url};
  $item->{0}->{props}->{key} = $v if defined $v;
  return $item;
}; # use_url_as_key

$Straw::ItemStep->{select_props} = sub {
  my ($item, $step) = @_;
  my $out = {};
  my @field = (defined $step->{fields} && ref $step->{fields} eq 'ARRAY')
      ? @{$step->{fields} || []} : ();
  for (@field) {
    $out->{0}->{props}->{$_} = $item->{0}->{props}->{$_}
        if defined $item->{0}->{props}->{$_};
  }
  return $out;
}; # select_props

$Straw::ItemStep->{set_if_defined} = sub {
  my ($item, $step) = @_;
  my @field = (defined $step->{fields} && ref $step->{fields} eq 'ARRAY')
      ? @{$step->{fields} || []} : ();
  my $src_channel = $step->{source_channel_id} // 1;
  for (@field) {
    $item->{0}->{props}->{$_} = $item->{$src_channel}->{props}->{$_}
         if defined $item->{0} and
            defined $item->{$src_channel} and
            defined $item->{$src_channel}->{props}->{$_};
  }
  return $item;
}; # set_if_defined

1;
