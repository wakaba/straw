package Straw::Stream;
use strict;
use warnings;
use Web::DateTime::Parser;
use Web::URL::Canonicalize;
use Web::DOM::Document;

our $ItemProcessor ||= {};

$ItemProcessor->{rss_basic} = sub {
  my $item = $_[0];
  {
    my $v = $item->{props}->{'http://purl.org/rss/1.0/title'};
    if (defined $v and @$v and length $v->[0]) {
      $item->{props}->{title} = $v->[0];
    }
  }
  {
    my $v = $item->{props}->{'http://purl.org/rss/1.0/link'};
    if (defined $v and @$v and length $v->[0]) {
      my $x = url_to_canon_url $v->[0], 'about:blank';
      $item->{props}->{url} = $x if defined $x;
    }
  }
  return $item;
}; # rss_basic

$ItemProcessor->{rss_desc_text} = sub {
  my $item = $_[0];
  my $v = $item->{props}->{'http://purl.org/rss/1.0/description'};
  if (defined $v and @$v and length $v->[0]) {
    $item->{props}->{desc_text} = $v->[0];
  }
  return $item;
}; # rss_desc_text

$ItemProcessor->{dc_date_as_timestamp} = sub {
  my $item = $_[0];
  my $v = $item->{props}->{'http://purl.org/dc/elements/1.1/date'};
  if (defined $v and @$v and length $v->[0]) {
    my $parser = Web::DateTime::Parser->new;
    my $dt = $parser->parse_w3c_dtf_string ($v->[0]);
    $item->{props}->{timestamp} = $dt->to_unix_number if defined $dt;
  }
  return $item;
}; # dc_date_as_timestamp

$ItemProcessor->{bookmark_entry_image} = sub {
  my $item = $_[0];
  my $v = $item->{props}->{'http://purl.org/rss/1.0/modules/content/encoded'};
  if (defined $v and @$v and length $v->[0]) {
    my $doc = new Web::DOM::Document;
    $doc->manakai_is_html (1);
    $doc->inner_html ($v->[0]);
    my $img = $doc->query_selector ('blockquote > p > a > img:only-child');
    if (defined $img) {
      my $url = $img->src;
      $item->{props}->{entry_image_url} = $url if length $url;
    }
  }
  return $item;
}; # bookmark_entry_image

$ItemProcessor->{cleanup_title} = sub {
  my $item = $_[0];
  my $v = $item->{props}->{title};
  if (defined $v) {
    $v =~ s/\s+/ /g;
    $v =~ s/^ //;
    $v =~ s/ $//;
    $item->{props}->{title} = $v if length $v;
  }
  return $item;
}; # cleanup_title

1;
