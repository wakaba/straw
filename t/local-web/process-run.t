use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

my $wait = web_server;

test {
  my $c = shift;
  my $stream;
  my $process;
  my $source;
  my $sink;
  return remote ($c, {
    a => [{'Content-Type' => 'text/xml'}, q{
      <rdf:RDF
        xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        xmlns="http://purl.org/rss/1.0/"
        xmlns:dc="http://purl.org/dc/elements/1.1/"
        xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel rdf:about="https://url/feed">
          <title>Hoge Feed</title>
          <link>https://url/</link>
          <description>This is Hoge Feed</description>
          <items>
            <rdf:Seq>
              <rdf:li rdf:resource="https://url/item/1" />
              <rdf:li rdf:resource="https://url/item/2" />
            </rdf:Seq>
          </items>
        </channel>
        <item rdf:about="https://url/item/1.rss">
          <title>Feed Entry 1</title>
          <link>https://url/item/1</link>
          <description>This is Feed Entry 1</description>
          <content:encoded>
            &lt;p lang=en>This is Feed Entry 1.&lt;/p>
            &lt;p lang=ja>Kore ha Feed Entry 1 desu.&lt;/p>
          </content:encoded>
          <dc:date>2015-12-01T11:46:23+09:00</dc:date>
        </item>
        <item rdf:about="https://url/item/2.rss">
          <title>Feed Entry 2</title>
          <link>https://url/item/2</link>
          <description>This is Feed Entry 2</description>
          <content:encoded>
            &lt;p lang=en>This is Feed Entry 2.&lt;/p>
            &lt;p lang=ja>Kore ha Feed Entry 2 desu.&lt;/p>
          </content:encoded>
          <dc:date>2015-12-02T11:46:23+09:00</dc:date>
        </item>
      </rdf:RDF>
    }],
  })->then (sub {
    return create_source ($c,
      fetch => {url => $_[0]->{a}},
    );
  })->then (sub {
    $source = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream = $_[0];
    return create_sink ($c, $stream);
  })->then (sub {
    $sink = $_[0];
    return create_process ($c, $source => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
    ] => $stream);
  })->then (sub {
    $process = $_[0];
    return POST ($c, qq{/source/$source->{source_id}/enqueue}, {});
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 202;
    } $c;
    return wait_drain $c;
  })->then (sub {
    return GET ($c, qq{/sink/$sink->{sink_id}/items});
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 200;
      is $res->header ('Content-Type'), 'application/json; charset=utf-8';
      my $json = json_bytes2perl $res->content;
      is 0+@{$json->{items}}, 2;
      my $item1 = $json->{items}->[0];
      is $item1->{url}, q<https://url/item/2>;
      is $item1->{title}, q<Feed Entry 2>;
      my $item2 = $json->{items}->[1];
      is $item2->{url}, q<https://url/item/1>;
      is $item2->{title}, q<Feed Entry 1>;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 8, name => 'fetch & process ok';

run_tests;
stop_web_server;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

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
