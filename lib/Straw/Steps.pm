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

$Straw::ItemStep->{set_key} = sub {
  my ($self, $step, $item, $result) = @_;
  my $key = $step->{field} // die "No |field| specified for the step";
  my $v = $item->{0}->{props}->{$key};
  $item->{0}->{props}->{key} = $v if defined $v and length $v;
  return $item;
}; # set_key

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

#XXX
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
