package Straw::Step::Fetch;
use strict;
use warnings;
use Web::MIME::Type;
use Web::DOM::Document;
use Web::HTML::Parser;
use Web::XML::Parser;

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

use Straw::Fetch;
$Straw::ItemStep->{fetch_item_url} = sub {
  my $item = $_[0];
  my $self = $_[2];
  my $result = $_[3];
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

1;
