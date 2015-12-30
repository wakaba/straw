package Straw::Step::HTML;
use strict;
use warnings;
use Web::DateTime::Parser;

$Straw::Step->{parse_html} = {
  in_type => 'Document',
  code => sub {
    my $in = $_[2];
    my $out = {type => 'Stream', props => {}, items => []};
    my $x = $in->{document}->title;
    $out->{props}->{title} = $x if length $x;
#    for (@{$in->{document}->query_selector_all ('.additional-list > li')}) {
    for (@{$in->{document}->query_selector_all ('.post')}) {
      my $item = {};

      my $video = $_->query_selector ('video');
      if (defined $video) {
        $item->{props}->{video_url} = $video->src;
      }

      #my $link = $_->query_selector ('a');
      my $link = $_->query_selector ('.time a');
      if (defined $link) {
        $link = $link->clone_node (1);
        for (@{$link->query_selector_all ('rt, rp')}) {
          my $parent = $_->parent_node;
          $parent->remove_child ($_) if defined $parent;
        }
        #$item->{props}->{title} = $link->text_content;
        $item->{props}->{url} = $link->href;
      }

      my $user = $_->query_selector ('h2 + a');
      if (defined $user) {
        $item->{props}->{author_name} = $user->text_content;
        $item->{props}->{author_url} = $user->href;
      }

      my $url = $_->query_selector ('h2 a');
      if (defined $url) {
        $item->{props}->{url} = $url->href;
      }

      my $desc = $_->query_selector ('.description');
      if (defined $desc) {
        $item->{props}->{title} = $desc->text_content;
      }

      my $time = $_->query_selector ('p:-manakai-contains("Uploaded at")');
      if (defined $time) {
        if ($time->text_content =~ /Uploaded at (\S+)/) {
          my $parser = Web::DateTime::Parser->new;
          my $dt = $parser->parse_html_datetime_value ($1);
          $item->{props}->{timestamp} = $dt->to_unix_number if defined $dt;
        }
      }

      push @{$out->{items}}, {0 => $item} if keys %$item;
    }
    return $out;
  },
}; # parse_html

1;
