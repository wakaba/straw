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
      <rss>
        <title>Hoge Feed</title>
        <link>https://url/</link>
        <description>This is Hoge Feed</description>
        <item>
          <title>Feed Entry(第13回)</title>
          <link>https://url/item/1</link>
          <description>This is Feed Entry 1</description>
          <dc:date>2015-12-01T11:46:23+09:00</dc:date>
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
    use utf8;
    return create_process ($c, $source => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'set_key', field => 'url'},
      {name => 'delete_substring',
       field => 'title',
       regexp => '\(第([0-9]+)回\)$',
       dest_fields => ['s1', 's2', 's3']},
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
      is 0+@{$json->{items}}, 1;
      my $item1 = $json->{items}->[0];
      is $item1->{data}->{title}, q<Feed Entry>;
      use utf8;
      is $item1->{data}->{s1}, q<(第13回)>;
      is $item1->{data}->{s2}, q<13>;
      is $item1->{data}->{s3}, undef;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 8, name => 'delete_substring matched';

test {
  my $c = shift;
  my $stream;
  my $process;
  my $source;
  my $sink;
  return remote ($c, {
    a => [{'Content-Type' => 'text/xml'}, q{
      <rss>
        <title>Hoge Feed</title>
        <link>https://url/</link>
        <description>This is Hoge Feed</description>
        <item>
          <title>Feed Entry(第13回?)</title>
          <link>https://url/item/1</link>
          <description>This is Feed Entry 1</description>
          <dc:date>2015-12-01T11:46:23+09:00</dc:date>
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
    use utf8;
    return create_process ($c, $source => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'set_key', field => 'url'},
      {name => 'delete_substring',
       field => 'title',
       regexp => '\(第([0-9]+)回\)$',
       dest_fields => ['s1', 's2', 's3']},
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
      is 0+@{$json->{items}}, 1;
      my $item1 = $json->{items}->[0];
      use utf8;
      is $item1->{data}->{title}, q<Feed Entry(第13回?)>;
      is $item1->{data}->{s1}, undef;
      is $item1->{data}->{s2}, undef;
      is $item1->{data}->{s3}, undef;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 8, name => 'delete_substring not matched';

run_tests;
stop_web_server;

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
