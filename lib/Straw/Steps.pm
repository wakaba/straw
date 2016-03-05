package Straw::Steps;
use strict;
use warnings;
use Time::HiRes qw(time);
use Digest::SHA qw(sha1_hex);
use JSON::PS;
use Promise;
use Dongry::Type;
use Dongry::Type::JSONPS;
use Web::URL::Canonicalize;
use Web::DateTime::Parser;
use Web::MIME::Type;
use Web::DOM::Document;
use Web::HTML::Parser;
use Web::XML::Parser;

$Straw::Step ||= {};
$Straw::ItemStep ||= {};

$Straw::Step->{httpres_to_doc} = {
  in_type => 'HTTP::Response',
  code => sub {
    my $in = $_[2];
    my $res = $in->{res};
    my $mime = Web::MIME::Type->parse_web_mime_type
        (scalar $res->header ('Content-Type'));
    # XXX MIME sniffing
    if (not defined $mime) {
      die "No MIME type";
    } elsif ($mime->as_valid_mime_type_with_no_params eq 'text/html') {
      my $parser = Web::HTML::Parser->new;
      my $doc = new Web::DOM::Document;
      $parser->parse_byte_string
          ($mime->param ('charset'), $res->content => $doc);
      $doc->manakai_set_url ($in->{url}); # XXX redirect
      return {type => 'Document', document => $doc};
    } elsif ($mime->is_xml_mime_type) {
      my $parser = Web::XML::Parser->new;
      my $doc = new Web::DOM::Document;
      $parser->parse_byte_string
          ($mime->param ('charset'), $res->content => $doc);
      $doc->manakai_set_url ($in->{url}); # XXX redirect
      return {type => 'Document', document => $doc};
    } else {
      die "Unknown MIME type";
    }
  },
}; # httpres_to_doc

$Straw::Step->{httpres_to_json} = {
  in_type => 'HTTP::Response',
  code => sub {
    my $in = $_[2];
    my $res = $in->{res};
    return {type => 'Object', object => json_bytes2perl $res->content};
  },
}; # httpres_to_json

use Straw::Fetch; # XXX
$Straw::ItemStep->{fetch_item_url} = sub {
  my ($self, $step, $item, $result) = @_;
  my $url = $item->{0}->{props}->{url};
  if (defined $url) {
    my $fetch = Straw::Fetch->new_from_db ($self->db); # XXX
    # XXX return
    $fetch->add_fetch_task ({
      url => $url,
    });
    $result->{fetch} = 1;
  }
  return $item;
}; # fetch_item_url

$Straw::Step->{parse_rss} = {
  in_type => 'Document',
  code => sub {
    my $in = $_[2];
    my $doc_el = $in->{document}->document_element;
    my $stream = {type => 'Stream', props => {}, items => []};
    if (defined $doc_el) {
      if ($doc_el->manakai_element_type_match (q<http://www.w3.org/1999/02/22-rdf-syntax-ns#>, 'RDF')) {
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
      } elsif ($doc_el->manakai_element_type_match ('http://www.w3.org/2005/Atom', 'feed')) {
        for my $el (@{$doc_el->children}) {
          if ($el->manakai_element_type_match ('http://www.w3.org/2005/Atom', 'entry')) {
            my $item = {};
            for my $el (@{$el->children}) {
              if ($el->local_name eq 'link' and
                  ($el->namespace_uri // '') eq 'http://www.w3.org/2005/Atom') {
                my $rel = $el->rel;
                $rel = q<http://www.iana.org/assignments/relation/alternate>
                    unless length $rel;
                my $val = {href => $el->href,
                           hreflang => $el->hreflang,
                           type => $el->type,
                           title => $el->title};
                for (qw(hreflang type title)) {
                  delete $val->{$_} unless length $val->{$_};
                }
                push @{$item->{props}->{$rel} ||= []}, $val;
              } else {
                push @{$item->{props}->{$el->manakai_expanded_uri} ||= []}, $el->text_content;
              }
            }
            push @{$stream->{items}}, {0 => $item};
          }
        }
      }
    } # $doc_el
    return $stream;
  },
}; # parse_rss

$Straw::ItemStep->{rss_basic} = sub {
  my ($self, $step, $item, $result) = @_;
  {
    my $v = $item->{0}->{props}->{'http://purl.org/rss/1.0/title'};
    if (defined $v and @$v and length $v->[0]) {
      $item->{0}->{props}->{title} = $v->[0];
    }
  }
  {
    my $v = $item->{0}->{props}->{'http://www.w3.org/2005/Atomtitle'};
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
  my ($self, $step, $item, $result) = @_;
  my $v = $item->{0}->{props}->{'http://purl.org/rss/1.0/description'};
  if (defined $v and @$v and length $v->[0]) {
    $item->{0}->{props}->{desc_text} = $v->[0];
  }
  return $item;
}; # rss_desc_text

$Straw::ItemStep->{dc_date_as_timestamp} = sub {
  my ($self, $step, $item, $result) = @_;
  my $v = $item->{0}->{props}->{'http://purl.org/dc/elements/1.1/date'};
  if (defined $v and @$v and length $v->[0]) {
    my $parser = Web::DateTime::Parser->new;
    my $dt = $parser->parse_w3c_dtf_string ($v->[0]);
    $item->{0}->{props}->{timestamp} = $dt->to_unix_number if defined $dt;
  }
  return $item;
}; # dc_date_as_timestamp

$Straw::ItemStep->{atom_updated_as_timestamp} = sub {
  my ($self, $step, $item, $result) = @_;
  my $v = $item->{0}->{props}->{'http://www.w3.org/2005/Atomupdated'};
  if (defined $v and @$v and length $v->[0]) {
    my $parser = Web::DateTime::Parser->new;
    my $dt = $parser->parse_rfc3339_xs_date_time_string ($v->[0]);
    $item->{0}->{props}->{timestamp} = $dt->to_unix_number if defined $dt;
  }
  return $item;
}; # atom_updated_as_timestamp

$Straw::Step->{extract_elements} = {
  in_type => 'Document',
  code => sub {
    my $step = $_[1];
    my $in = $_[2];
    my $out = {type => 'Stream', props => {}};

    my $x = $in->{document}->title;
    $out->{props}->{title} = $x if length $x;

    $out->{items} = [map {
      {0 => {element => $_}};
    } $in->{document}->query_selector_all ($step->{path})->to_list];

    return $out;
  },
}; # extract_elements

$Straw::ItemStep->{set_text_prop_from_element} = sub {
  my ($self, $step, $item, $result) = @_;
  die "No |element|" unless defined $item->{0} and defined $item->{0}->{element};
  my $el = $item->{0}->{element}->query_selector ($step->{path});
  return $item unless defined $el;
  $item->{0}->{props}->{$step->{field}} = $el->text_content;
  return $item;
}; # set_text_prop_from_element

$Straw::ItemStep->{set_url_prop_from_element} = sub {
  my ($self, $step, $item, $result) = @_;
  die "No |element|" unless defined $item->{0} and defined $item->{0}->{element};
  my $el = $item->{0}->{element}->query_selector ($step->{path});
  return $item unless defined $el;
  my $url;
  $url = $el->href if $el->can ('href');
  $item->{0}->{props}->{$step->{field}} = $url if defined $url and length $url;
  return $item;
}; # set_url_prop_from_element

$Straw::ItemStep->{set_time_prop_from_element} = sub {
  my ($self, $step, $item, $result) = @_;
  die "No |element|" unless defined $item->{0} and defined $item->{0}->{element};
  my $el = $item->{0}->{element}->query_selector ($step->{path});
  return $item unless defined $el;
  my $time;
  $time = $el->datetime if $el->can ('datetime');
  $time = $el->text_content if not defined $time or not length $time;
  if (defined $time and length $time) {
    my $parser = Web::DateTime::Parser->new;
    my $dt = $parser->parse_html_datetime_value ($time);
    $item->{0}->{props}->{$step->{field}} = $dt->to_unix_number if defined $dt;
  }
  return $item;
}; # set_time_prop_from_element

$Straw::ItemStep->{dump_to_prop_from_element} = sub {
  my ($self, $step, $item, $result) = @_;
  unless (defined $item->{0} and defined $item->{0}->{element}) {
    $item->{0}->{props}->{$step->{field}} = "No |element}";
  } else {
    my $el = $item->{0}->{element}->query_selector ($step->{path});
    unless (defined $el) {
      $item->{0}->{props}->{$step->{field}} = "No match ($step->{path})";
    } else {
      $item->{0}->{props}->{$step->{field}} = $el->outer_html;
    }
  }
  return $item;
}; # dump_to_prop_from_element

$Straw::Step->{dump_stream} = {
  in_type => 'Stream',
  code => sub {
    my $in = $_[2];
    $_[0]->debug (perl2json_chars_for_record $in);
    return $in;
  },
}; # dump_stream

$Straw::ItemStep->{use_alternate_link_as_url} = sub {
  my ($self, $step, $item, $result) = @_;
  my $v = $item->{0}->{props}->{q<http://www.iana.org/assignments/relation/alternate>};
  if (defined $v and ref $v eq 'ARRAY') {
    my @w = grep {
      defined $_->{href} and length $_->{href};
    } @$v;
    if (@w) {
      $item->{0}->{props}->{url} = $w[0]->{href};
    }
  }
  return $item;
}; # use_alternate_link_as_url

$Straw::ItemStep->{set_key} = sub {
  my ($self, $step, $item, $result) = @_;
  my $key = $step->{field} // die "No |field| specified for the step";
  my $v = $item->{0}->{props}->{$key};
  $item->{0}->{props}->{key} = $v if defined $v and length $v;
  return $item;
}; # set_key

$Straw::ItemStep->{use_url_as_key} = sub {
  my ($self, $step, $item, $result) = @_;
  my $v = $item->{0}->{props}->{url};
  $item->{0}->{props}->{key} = $v if defined $v and length $v;
  return $item;
}; # use_url_as_key

$Straw::ItemStep->{use_atom_id_as_key} = sub {
  my ($self, $step, $item, $result) = @_;
  my $v = $item->{0}->{props}->{q<http://www.w3.org/2005/Atomid>};
  if (defined $v and ref $v eq 'ARRAY' and @$v) {
    $item->{0}->{props}->{key} = $v->[0] if length $v->[0];
  }
  return $item;
}; # use_atom_id_as_key

$Straw::ItemStep->{select_props} = sub {
  my ($self, $step, $item, $result) = @_;
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
  my ($self, $step, $item, $result) = @_;
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

$Straw::ItemStep->{bookmark_entry_image} = sub {
  my ($self, $step, $item, $result) = @_;
  my $v = $item->{0}->{props}->{'http://purl.org/rss/1.0/modules/content/encoded'};
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
  my ($self, $step, $item, $result) = @_;
  my $v = $item->{0}->{props}->{title};
  if (defined $v) {
    $v =~ s/\s+/ /g;
    $v =~ s/^ //;
    $v =~ s/ $//;
    $item->{props}->{title} = $v if length $v;
  }
  return $item;
}; # cleanup_title

$Straw::Step->{extract_array_items} = {
  in_type => 'Object',
  code => sub {
    my $step = $_[1];
    my $in = $_[2];
    my $path = $step->{path} // '';
    die "Bad path |$path|" unless $path =~ m{^/};
    my @path = split m{/}, $path, -1;
    shift @path;
    my $list;
    my $v = $in->{object};
    if (@path) {
      my $last = pop @path;
      my @current;
      while (@path) {
        my $p = shift @path;
        push @current, $p;
        if (defined $v and ref $v eq 'HASH') {
          $v = $v->{$p};
        } else {
          die "|@current| is not an object";
        }
      }
      if (defined $v->{$last} and ref $v->{$last} eq 'ARRAY') {
        $list = $v->{$last};
      } else {
        push @current, $last;
        die "|@current| is not an array";
      }
    } else {
      if (defined $v and ref $v eq 'ARRAY') {
        $list = $v;
      } else {
        die "|/| is not an array";
      }
    }
    
    my $out = {type => 'Stream', props => {}, items => []};
    push @{$out->{items}}, map { +{0 => {props => $_}} } @$list;

    return $out;
  },
}; # extract_array_items

1;

=head1 LICENSE

Copyright 2015-2016 Wakaba <wakaba@suikawiki.org>.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Affero General Public License for more details.

You does not have received a copy of the GNU Affero General Public
License along with this program, see <http://www.gnu.org/licenses/>.

=cut
