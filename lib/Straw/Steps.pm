package Straw::Steps;
use strict;
use warnings;
use Time::HiRes qw(time);
use Digest::SHA qw(sha1_hex);
use JSON::PS;
use Promise;
use Dongry::Type;
use Dongry::Type::JSONPS;
use Web::DateTime::Parser;
use Web::MIME::Type;
use Web::DOM::Document;
use Web::HTML::Parser;
use Web::XML::Parser;
use Web::Feed::Parser;

$Straw::Step ||= {};
$Straw::ItemStep ||= {};

$Straw::Step->{url_prefix_filter} = {
  in_type => 'HTTP::Response',
  code => sub {
    my $step = $_[1];
    my $in = $_[2];
    my $value = $step->{value};
    if (not defined $value or not $in->{url} =~ m{\A\Q$value\E}) {
      return {type => 'Null'};
    }
    return $in;
  },
}; # url_prefix_filter

$Straw::Step->{url_suffix_filter} = {
  in_type => 'HTTP::Response',
  code => sub {
    my $step = $_[1];
    my $in = $_[2];
    my $value = $step->{value};
    if (not defined $value or not $in->{url} =~ m{\Q$value\E\z}) {
      return {type => 'Null'};
    }
    return $in;
  },
}; # url_suffix_filter

$Straw::ItemStep->{item_url_prefix_filter} = sub {
  my ($self, $step, $item) = @_;
  my $value = $step->{value};
  if (not defined $value or
      not defined $item->{0}->{props}->{url} or
      not $item->{0}->{props}->{url} =~ m{\A\Q$value\E}) {
    return undef;
  }
  return $item;
}; # item_url_prefix_filter

$Straw::ItemStep->{item_url_suffix_filter} = sub {
  my ($self, $step, $item) = @_;
  my $value = $step->{value};
  if (not defined $value or
      not defined $item->{0}->{props}->{url} or
      not $item->{0}->{props}->{url} =~ m{\Q$value\E\z}) {
    return undef;
  }
  return $item;
}; # item_url_suffix_filter

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
  my ($self, $step, $item) = @_;
  my $url = $item->{0}->{props}->{url};
  if (defined $url) {
    my $fetch = Straw::Fetch->new_from_db ($self->db); # XXX
    # XXX return
    $fetch->add_fetch_task ({
      url => $url,
    });
  }
  return $item;
}; # fetch_item_url

$Straw::Step->{parse_rss} = {
  in_type => 'Document',
  code => sub {
    my $in = $_[2];
    my $stream = {type => 'Stream', props => {}, items => []};

    my $parser = Web::Feed::Parser->new;
    my $parsed = $parser->parse_document ($in->{document});

    if (defined $parsed) {
      my $c = sub {
        my $v = $_[0];

        if (defined $v->{title} and
            UNIVERSAL::can ($v->{title}, 'text_content')) {
          $v->{title} = $v->{title}->text_content;
        }

        if (defined $v->{summary}) {
          if (UNIVERSAL::can ($v->{summary}, 'text_content')) {
            $v->{desc_text} = (delete $v->{summary})->text_content;
          } else {
            $v->{desc_text} = delete $v->{summary};
          }
        }

        if (defined $v->{content}) {
          if (UNIVERSAL::can ($v->{content}, 'text_content')) {
            $v->{content_text} = (delete $v->{content})->text_content;
          } else {
            $v->{content_text} = delete $v->{content};
          }
        }

        if (defined $v->{updated} and
            UNIVERSAL::can ($v->{updated}, 'to_unix_number')) {
          $v->{timestamp} = $v->{updated}->to_unix_number;
        } elsif (defined $v->{created} and
                 UNIVERSAL::can ($v->{created}, 'to_unix_number')) {
          $v->{timestamp} = $v->{created}->to_unix_number;
        } elsif (defined $parsed->{updated} and
                 UNIVERSAL::can ($parsed->{updated}, 'to_unix_number')) {
          $v->{timestamp} = $parsed->{updated};
        }

        $v->{url} = delete $v->{page_url} if defined $v->{page_url};

        return $v;
      }; # $c

      push @{$stream->{items}}, map { {0 => {props => $c->($_)}} } @{delete $parsed->{entries}};
    }

    return $stream;
  },
}; # parse_rss

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
  my ($self, $step, $item) = @_;
  die "No |element|" unless defined $item->{0} and defined $item->{0}->{element};
  my $el = $item->{0}->{element};
  $el = $el->query_selector ($step->{path})
      if defined $step->{path} and length $step->{path};
  return $item unless defined $el;
  if (defined $step->{attr} and length $step->{attr}) {
    $item->{0}->{props}->{$step->{field}} = $el->get_attribute ($step->{attr});
  } else {
    my $tree = $el->clone_node (1);
    for ($tree->query_selector_all ('style, script')->to_list) {
      $_->parent_node->remove_child ($_);
    }
    for ($tree->query_selector_all ('br')->to_list) {
      $_->parent_node->replace_child ($_->owner_document->create_text_node ("\x0A"), $_);
    }
    $item->{0}->{props}->{$step->{field}} = $tree->text_content;
  }
  return $item;
}; # set_text_prop_from_element

$Straw::ItemStep->{set_html_prop_from_element} = sub {
  my ($self, $step, $item) = @_;
  die "No |element|" unless defined $item->{0} and defined $item->{0}->{element};
  my $el = $item->{0}->{element};
  $el = $el->query_selector ($step->{path})
      if defined $step->{path} and length $step->{path};
  return $item unless defined $el;
  $item->{0}->{props}->{$step->{field}} = $el->inner_html;
  return $item;
}; # set_html_prop_from_element

$Straw::ItemStep->{set_boolean_prop_by_has_element} = sub {
  my ($self, $step, $item) = @_;
  die "No |element|" unless defined $item->{0} and defined $item->{0}->{element};
  my $el = $item->{0}->{element};
  $el = $el->query_selector ($step->{path})
      if defined $step->{path} and length $step->{path};
  $item->{0}->{props}->{$step->{field}} = !!$el;
  return $item;
}; # set_boolean_prop_from_element_class

$Straw::ItemStep->{set_url_prop_from_element} = sub {
  my ($self, $step, $item) = @_;
  die "No |element|" unless defined $item->{0} and defined $item->{0}->{element};
  my $el = $item->{0}->{element};
  $el = $el->query_selector ($step->{path})
      if defined $step->{path} and length $step->{path};
  return $item unless defined $el;
  my $url;
  if (defined $step->{attr} and length $step->{attr}) {
    my $x = $el->owner_document->create_element_ns ('http://www.w3.org/1999/xhtml', 'a');
    $x->href ($el->get_attribute ($step->{attr}));
    $url = $x->href;
  } else {
    $url = $el->href if $el->can ('href');
    $url = $el->src if not (defined $url and length $url) and $el->can ('src');
  }
  $item->{0}->{props}->{$step->{field}} = $url if defined $url and length $url;
  return $item;
}; # set_url_prop_from_element

$Straw::ItemStep->{set_time_prop_from_element} = sub {
  my ($self, $step, $item) = @_;
  die "No |element|" unless defined $item->{0} and defined $item->{0}->{element};
  my $el = $item->{0}->{element};
  $el = $el->query_selector ($step->{path})
      if defined $step->{path} and length $step->{path};
  return $item unless defined $el;
  my $time;
  if (defined $step->{attr} and length $step->{attr}) {
    $time = $el->get_attribute ($step->{attr});
  } else {
    $time = $el->datetime if $el->can ('datetime');
    $time = $el->text_content if not defined $time or not length $time;
  }
  if (defined $time and length $time) {
    my $parser = Web::DateTime::Parser->new;
    my $dt = $parser->parse_html_datetime_value ($time);
    $item->{0}->{props}->{$step->{field}} = $dt->to_unix_number if defined $dt;
  }
  return $item;
}; # set_time_prop_from_element

$Straw::ItemStep->{dump_to_prop_from_element} = sub {
  my ($self, $step, $item) = @_;
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

$Straw::ItemStep->{append_text_to_prop} = sub {
  my ($self, $step, $item) = @_;
  my $value = $step->{value};
  if (defined $value) {
    $item->{0}->{props}->{$step->{field}} = ''
        unless defined $item->{0}->{props}->{$step->{field}};
    $item->{0}->{props}->{$step->{field}} .= $value;
  }
  return $item;
}; # append_text_to_prop

$Straw::ItemStep->{delete_substring} = sub {
  my ($self, $step, $item) = @_;

  my $props = $item->{0}->{props};
  my $value = $props->{$step->{field}};
  return $item unless defined $value;

  die "|regexp| not specified" unless defined $step->{regexp};
  my $dest = $step->{dest_fields} || [];
  my $regexp = qr/$step->{regexp}/;
  $value =~ s{$regexp}{
    for my $i (0..$#$dest) {
      next unless defined $dest->[$i];
      $props->{$dest->[$i]} = substr $value, $-[$i], $+[$i]-$-[$i]
          if defined $+[$i];
    }
    '';
  }e;
  $props->{$step->{field}} = $value;

  return $item;
}; # delete_substring

$Straw::Step->{dump_stream} = {
  in_type => 'Stream',
  code => sub {
    my $in = $_[2];
    $_[0]->debug (perl2json_chars_for_record $in);
    return $in;
  },
}; # dump_stream

$Straw::ItemStep->{set_key} = sub {
  my ($self, $step, $item) = @_;
  my $key = $step->{field} // die "No |field| specified for the step";
  my $v = $item->{0}->{props}->{$key};
  $item->{0}->{props}->{key} = $v if defined $v and length $v;
  return $item;
}; # set_key

$Straw::ItemStep->{set_key_by_template} = sub {
  my ($self, $step, $item) = @_;
  my $v = $step->{template} // die "No |template| specified for the step";
  $v =~ s{\{([A-Za-z0-9_]+)\}}{$item->{0}->{props}->{$1} // ''}ge;
  $item->{0}->{props}->{key} = $v if length $v;
  return $item;
}; # set_key_by_template

$Straw::ItemStep->{set_timestamp} = sub {
  my ($self, $step, $item) = @_;
  my $key = $step->{field} // die "No |field| specified for the step";
  my $v = $item->{0}->{props}->{$key};
  $item->{0}->{props}->{timestamp} = 0+$v if defined $v and length $v;
  return $item;
}; # set_timestamp

$Straw::ItemStep->{select_props} = sub {
  my ($self, $step, $item) = @_;
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
  my ($self, $step, $item) = @_;
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

#XXX
$Straw::ItemStep->{bookmark_entry_image} = sub {
  my ($self, $step, $item) = @_;
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
  my ($self, $step, $item) = @_;
  my $v = $item->{0}->{props}->{title};
  if (defined $v) {
    $v =~ s/\s+/ /g;
    $v =~ s/^ //;
    $v =~ s/ $//;
    $item->{props}->{title} = $v if length $v;
  }
  return $item;
}; # cleanup_title

sub _get_from_object_by_path ($$) {
  my ($v, $path) = @_;
  die "Bad path |$path|" unless $path =~ m{^/};
  my @path = split m{/}, $path, -1;
  shift @path;
  if (@path and not (@path == 1 and $path[0] eq '')) {
    my $last = pop @path;
    my @current;
    while (@path) {
      my $p = shift @path;
      if (defined $v and ref $v eq 'HASH') {
        push @current, $p;
        $v = $v->{$p};
      } else {
        die "|@current| is not an object";
      }
    }
    return $v->{$last};
  } else {
    return $v;
  }
} # _get_from_object_by_path

$Straw::Step->{extract_array_items} = {
  in_type => 'Object',
  code => sub {
    my $step = $_[1];
    my $in = $_[2];

    die "There is no object" unless defined $in->{object};
    my $list = _get_from_object_by_path $in->{object}, $step->{path};
    die "|$in->{path}| is not an array"
        unless defined $list and ref $list eq 'ARRAY';
    
    my $out = {type => 'Stream', props => {}, items => []};
    push @{$out->{items}}, map { +{0 => {props => $_}} } @$list;

    return $out;
  },
}; # extract_array_items

$Straw::ItemStep->{set_text_prop_by_path} = sub {
  my ($self, $step, $item) = @_;

  my $v = _get_from_object_by_path $item->{0}->{props}, $step->{path};
  $item->{0}->{props}->{$step->{field}} = $v if defined $v;

  return $item;
}; # set_text_prop_by_path

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
