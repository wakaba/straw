package Straw::Step::RSS;
use strict;
use warnings;
use Web::URL::Canonicalize;
use Web::DateTime::Parser;

$Straw::Step->{parse_rss} = {
  in_type => 'Document',
  code => sub {
    my $in = $_[2];
    my $doc_el = $in->{document}->document_element;
    my $stream = {type => 'Stream', props => {}, items => []};
    if (defined $doc_el and $doc_el->manakai_element_type_match (q<http://www.w3.org/1999/02/22-rdf-syntax-ns#>, 'RDF')) {
      for my $el (@{$doc_el->children}) {
        if ($el->manakai_element_type_match ('http://purl.org/rss/1.0/', 'channel')) {
          for my $el (@{$el->children}) {
            unless ($el->manakai_element_type_match ('http://purl.org/rss/1.0/', 'items')) {
              push @{$stream->{props}->{$el->manakai_expanded_uri} ||= []}, $el->text_content;
            }
          }
        } elsif ($el->manakai_element_type_match ('http://purl.org/rss/1.0/', 'item')) {
          my $item = {};
          for my $el (@{$el->children}) {
            push @{$item->{props}->{$el->manakai_expanded_uri} ||= []}, $el->text_content;
          }
          push @{$stream->{items}}, {0 => $item};
        }
      }
    }
    return $stream;
  },
}; # parse_rss


$Straw::ItemStep->{rss_basic} = sub {
  my $item = $_[0];
  {
    my $v = $item->{0}->{props}->{'http://purl.org/rss/1.0/title'};
    if (defined $v and @$v and length $v->[0]) {
      $item->{0}->{props}->{title} = $v->[0];
    }
  }
  {
    my $v = $item->{0}->{props}->{'http://purl.org/rss/1.0/link'};
    if (defined $v and @$v and length $v->[0]) {
      my $x = url_to_canon_url $v->[0], 'about:blank';
      $item->{0}->{props}->{url} = $x if defined $x;
    }
  }
  return $item;
}; # rss_basic

$Straw::ItemStep->{rss_desc_text} = sub {
  my $item = $_[0];
  my $v = $item->{0}->{props}->{'http://purl.org/rss/1.0/description'};
  if (defined $v and @$v and length $v->[0]) {
    $item->{0}->{props}->{desc_text} = $v->[0];
  }
  return $item;
}; # rss_desc_text

$Straw::ItemStep->{dc_date_as_timestamp} = sub {
  my $item = $_[0];
  my $v = $item->{0}->{props}->{'http://purl.org/dc/elements/1.1/date'};
  if (defined $v and @$v and length $v->[0]) {
    my $parser = Web::DateTime::Parser->new;
    my $dt = $parser->parse_w3c_dtf_string ($v->[0]);
    $item->{0}->{props}->{timestamp} = $dt->to_unix_number if defined $dt;
  }
  return $item;
}; # dc_date_as_timestamp

1;
