package Straw::Step::Fetch;
use strict;
use warnings;
use Promise;
use Web::UserAgent::Functions qw(http_get);
use Web::MIME::Type;
use Web::DOM::Document;
use Web::HTML::Parser;
use Web::XML::Parser;

#XXX
$Straw::Step->{url_to_httpres} = {
  in_type => 'URL',
  code => sub {
    my $in = $_[2];
    return Promise->new (sub {
      my ($ok, $ng) = @_;
      # XXX redirect
      http_get
          url => $in->{url},
          anyevent => 1,
          cb => sub {
            $ok->({type => 'HTTP::Response', res => $_[1]});
          };
    });
  },
}; # url_to_httpres

# XXX internal
use HTTP::Response;
$Straw::Step->{load_fetch_result} = {
  in_type => 'Empty',
  code => sub {
    my ($self, $step, $in) = @_;
    return $self->db->select ('fetch_result', {
      key => $step->{key},
    })->then (sub {
      my $data = $_[0]->first;
      if (defined $data) {
        return {type => 'HTTP::Response',
                res => HTTP::Response->parse ($data->{data})};
      } else {
        die "Fetched result for |$step->{key}| not found";
      }
    });
  },
};

$Straw::Step->{httpres_to_doc} = {
  in_type => 'HTTP::Response',
  code => sub {
    my $in = $_[2];
    my $res = $in->{res};
    my $mime = Web::MIME::Type->parse_web_mime_type
        (scalar $res->header ('Content-Type'));
    # XXX MIME sniffing
    if ($mime->as_valid_mime_type_with_no_params eq 'text/html') {
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

1;
