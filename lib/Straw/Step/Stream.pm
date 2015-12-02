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
