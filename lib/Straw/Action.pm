package Straw::Action;
use strict;
use warnings;
use Promise;
use Web::MIME::Type;
use Web::DOM::Document;
use Web::HTML::Parser;
use Web::XML::Parser;
use Web::UserAgent::Functions qw(http_get);
use Dongry::Type;
use Dongry::Type::JSONPS;
use Straw::Stream;

sub new_from_db ($$) {
  return bless {db => $_[1]}, $_[0];
} # new_from_db

sub db ($) {
  return $_[0]->{db};
} # db

sub get_url ($$) {
  my $url = $_[1];
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    # XXX redirect
    http_get
        url => $url,
        anyevent => 1,
        cb => sub {
          my $res = $_[1];
          if ($res->code == 200) {
            $ok->($res);
          } else {
            $ng->($res);
          }
        };
  });
} # get_url

sub url_to_doc ($$) {
  my ($self, $in) = @_;
  return Promise->reject ("Bad type |$in->{type}|")
      unless $in->{type} eq 'url';
  return $self->get_url ($in->{url})->then (sub {
    my $res = $_[0];
    my $mime = Web::MIME::Type->parse_web_mime_type
        (scalar $res->header ('Content-Type'));
    # XXX MIME sniffing
    if ($mime->as_valid_mime_type_with_no_params eq 'text/html') {
      my $parser = Web::HTML::Parser->new;
      my $doc = new Web::DOM::Document;
      $parser->parse_byte_string
          ($mime->param ('charset'), $res->content => $doc);
      $doc->manakai_set_url ($in->{url}); # XXX redirect
      return {type => 'document', document => $doc};
    } elsif ($mime->is_xml_mime_type) {
      my $parser = Web::XML::Parser->new;
      my $doc = new Web::DOM::Document;
      $parser->parse_byte_string
          ($mime->param ('charset'), $res->content => $doc);
      $doc->manakai_set_url ($in->{url}); # XXX redirect
      return {type => 'document', document => $doc};
    } else {
      die "Unknown MIME type";
    }
  });
} # url_to_doc

sub parse_rss ($$) {
  my $in = $_[1];
  return Promise->reject ("Bad type |$in->{type}|")
      unless $in->{type} eq 'document';
  my $doc_el = $in->{document}->document_element;
  my $stream = {type => 'stream', props => {}, items => []};
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
        push @{$stream->{items}}, $item;
      }
    }
  }
  return $stream;
} # parse_rss

sub parse_html ($$) {
  my $in = $_[1];
  return Promise->reject ("Bad type |$in->{type}|")
      unless $in->{type} eq 'document';
  my $out = {type => 'stream', props => {}, items => []};
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

    push @{$out->{items}}, $item if keys %$item;
  }
  return $out;
} # parse_html

sub apply_stream_item_processor ($$$) {
  my ($self, $in, $rule) = @_;
  die "Bad type |$in->{type}|" unless $in->{type} eq 'stream';
  my $code = $Straw::Stream::ItemProcessor->{$rule} or die "Bad rule |$rule|";
  my $items = [];
  for my $item (@{$in->{items}}) {
    push @$items, $code->($item);
  }
  $in->{items} = $items;
  return $in;
} # apply_stream_item_processor

sub save_stream ($$) {
  my ($self, $in) = @_;
  return Promise->reject ("Bad type |$in->{type}|")
      unless $in->{type} eq 'stream';

  my $stream_id = 53; # XXX

  ## Stream metadata
  # XXX

  ## Stream items
  return Promise->resolve ($in) unless @{$in->{items}};
  return $self->db->insert ('stream_item', [map {
    my $key = undef;
    my $time = time;
    $key //= $time;
    +{
      stream_id => $stream_id,
      item_key => $key, # XXX
      data => Dongry::Type->serialize ('json', $_),
      stream_item_timestamp => $time,
    };
  } @{$in->{items}}], duplicate => 'replace')->then (sub { return $in });
} # save_stream

sub load_stream ($$) {
  my ($self, $in) = @_;
  return Promise->reject ("Bad type |$in->{type}|")
      unless $in->{type} eq 'streamref';

  my $out = {type => 'stream', items => []};
  return $self->db->select ('stream_item', {
    stream_id => Dongry::Type->serialize ('text', $in->{stream_id}),
    # XXX paging
  })->then (sub {
    for (@{$_[0]->all}) {
      push @{$out->{items}}, Dongry::Type->parse ('json', $_->{data});
    }
  })->then (sub {
    return $out;
  });
} # load_stream

1;
