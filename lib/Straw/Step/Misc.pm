package Straw::Step::Misc;
use strict;
use warnings;
use Web::DOM::Document;

$Straw::ItemStep->{bookmark_entry_image} = sub {
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

$Straw::ItemStep->{cleanup_title} = sub {
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
