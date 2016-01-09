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
      is $item1->{data}->{url}, q<https://url/item/2>;
      is $item1->{data}->{title}, q<Feed Entry 2>;
      ok $item1->{timestamp};
      my $item2 = $json->{items}->[1];
      is $item2->{data}->{url}, q<https://url/item/1>;
      is $item2->{data}->{title}, q<Feed Entry 1>;
      ok $item2->{timestamp};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 10, name => 'fetch & process ok';

test {
  my $c = shift;
  my $stream;
  my $stream2;
  my $process;
  my $process2;
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
    return create_stream ($c);
  })->then (sub {
    $stream2 = $_[0];
    return create_sink ($c, $stream2);
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
    return create_process ($c, $stream => [
      {name => 'rss_desc_text'},
    ] => $stream2);
  })->then (sub {
    $process2 = $_[0];
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
      is $item1->{data}->{url}, q<https://url/item/2>;
      is $item1->{data}->{title}, q<Feed Entry 2>;
      is $item1->{data}->{desc_text}, q{This is Feed Entry 2};
      my $item2 = $json->{items}->[1];
      is $item2->{data}->{url}, q<https://url/item/1>;
      is $item2->{data}->{title}, q<Feed Entry 1>;
      is $item2->{data}->{desc_text}, q{This is Feed Entry 1};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 10, name => 'stream subscripting process ok';

test {
  my $c = shift;
  my $urls;
  my $stream;
  my $stream2;
  my $process;
  my $process2;
  my $process3;
  my $source;
  my $source2;
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
      </rdf:RDF>
    }],
    b => [{'Content-Type' => 'text/xml'}, q{
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
    $urls = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{a}},
    );
  })->then (sub {
    $source = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{b}},
    );
  })->then (sub {
    $source2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream2 = $_[0];
    return create_sink ($c, $stream2);
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
    return create_process ($c, $source2 => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
    ] => $stream);
  })->then (sub {
    $process2 = $_[0];
    return create_process ($c, $stream => [
      {name => 'rss_desc_text'},
    ] => $stream2);
  })->then (sub {
    $process3 = $_[0];
    return enqueue_task ($c, $source);
  })->then (sub {
    return enqueue_task ($c, $source2);
  })->then (sub {
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
      is $item1->{data}->{url}, q<https://url/item/2>;
      is $item1->{data}->{title}, q<Feed Entry 2>;
      is $item1->{data}->{desc_text}, q{This is Feed Entry 2};
      my $item2 = $json->{items}->[1];
      is $item2->{data}->{url}, q<https://url/item/1>;
      is $item2->{data}->{title}, q<Feed Entry 1>;
      is $item2->{data}->{desc_text}, q{This is Feed Entry 1};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 9, name => 'multiple processes, one stream';

test {
  my $c = shift;
  my $urls;
  my $stream;
  my $stream2;
  my $stream3;
  my $process;
  my $process2;
  my $process3;
  my $source;
  my $source2;
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
              <rdf:li rdf:resource="https://url/item/1.rss" />
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
      </rdf:RDF>
    }],
    b => [{'Content-Type' => 'text/xml'}, q{
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
              <rdf:li rdf:resource="https://url/item/2.rss" />
            </rdf:Seq>
          </items>
        </channel>
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
    $urls = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{a}},
    );
  })->then (sub {
    $source = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{b}},
    );
  })->then (sub {
    $source2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream3 = $_[0];
    return create_sink ($c, $stream3);
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
    return create_process ($c, $source2 => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
    ] => $stream2);
  })->then (sub {
    $process2 = $_[0];
    return create_process ($c, [$stream, $stream2] => [
      {name => 'rss_desc_text'},
    ] => $stream3);
  })->then (sub {
    $process3 = $_[0];
    return enqueue_task ($c, $source);
  })->then (sub {
    return enqueue_task ($c, $source2);
  })->then (sub {
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
      my $items = [sort { $a->{data}->{url} cmp $b->{data}->{url} } @{$json->{items}}];
      my $item1 = $json->{items}->[1];
      is $item1->{data}->{url}, q<https://url/item/2>;
      is $item1->{data}->{title}, q<Feed Entry 2>;
      is $item1->{data}->{desc_text}, q{This is Feed Entry 2};
      my $item2 = $json->{items}->[0];
      is $item2->{data}->{url}, q<https://url/item/1>;
      is $item2->{data}->{title}, q<Feed Entry 1>;
      is $item2->{data}->{desc_text}, q{This is Feed Entry 1};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 9, name => 'multiple streams, merged into one stream by a process';

test {
  my $c = shift;
  my $urls;
  my $stream;
  my $stream2;
  my $stream3;
  my $process;
  my $process2;
  my $process3;
  my $source;
  my $source2;
  my $sink;
  my $sink2;
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
      </rdf:RDF>
    }],
    b => [{'Content-Type' => 'text/xml'}, q{
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
        <item rdf:about="https://url/item/2.rss">
          <title>Feed Entry 2</title>
          <link>https://url/item/1</link>
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
    $urls = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{a}},
    );
  })->then (sub {
    $source = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{b}},
    );
  })->then (sub {
    $source2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream3 = $_[0];
    return create_sink ($c, $stream3);
  })->then (sub {
    $sink = $_[0];
    return create_sink ($c, $stream3, channel_id => 52);
  })->then (sub {
    $sink2 = $_[0];
    return create_process ($c, $source => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
    ] => $stream);
  })->then (sub {
    $process = $_[0];
    return create_process ($c, $source2 => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
    ] => $stream2);
  })->then (sub {
    $process2 = $_[0];
    return create_process ($c, [$stream, $stream2] => [
      {name => 'rss_desc_text'},
    ] => $stream3, channel_map => {
      $stream2->{stream_id} => {0 => 52},
    });
  })->then (sub {
    $process3 = $_[0];
    return enqueue_task ($c, $source);
  })->then (sub {
    return enqueue_task ($c, $source2);
  })->then (sub {
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
      is $item1->{data}->{url}, q<https://url/item/1>;
      is $item1->{data}->{title}, q<Feed Entry 1>;
      is $item1->{data}->{desc_text}, q{This is Feed Entry 1};
    } $c;
    return GET ($c, qq{/sink/$sink2->{sink_id}/items});
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 200;
      is $res->header ('Content-Type'), 'application/json; charset=utf-8';
      my $json = json_bytes2perl $res->content;
      is 0+@{$json->{items}}, 1;
      my $item1 = $json->{items}->[0];
      is $item1->{data}->{url}, q<https://url/item/1>;
      is $item1->{data}->{title}, q<Feed Entry 2>;
      is $item1->{data}->{desc_text}, undef;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 12, name => 'channel mapped';

test {
  my $c = shift;
  my $urls;
  my $stream;
  my $stream2;
  my $stream3;
  my $process;
  my $process2;
  my $process3;
  my $source;
  my $source2;
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
      </rdf:RDF>
    }],
    b => [{'Content-Type' => 'text/xml'}, q{
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
        <item rdf:about="https://url/item/2.rss">
          <title>Feed Entry 2</title>
          <link>https://url/item/1</link>
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
    $urls = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{a}},
    );
  })->then (sub {
    $source = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{b}},
    );
  })->then (sub {
    $source2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream3 = $_[0];
    return create_sink ($c, $stream3);
  })->then (sub {
    $sink = $_[0];
    return create_process ($c, $source => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
      {name => 'rss_desc_text'},
    ] => $stream);
  })->then (sub {
    $process = $_[0];
    return create_process ($c, $source2 => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
      {name => 'rss_desc_text'},
    ] => $stream2);
  })->then (sub {
    $process2 = $_[0];
    return create_process ($c, [$stream, $stream2] => [
      {name => 'set_if_defined', fields => ['desc_text']},
    ] => $stream3, channel_map => {
      $stream2->{stream_id} => {0 => 1},
    });
  })->then (sub {
    $process3 = $_[0];
    return enqueue_task ($c, $source);
  })->then (sub {
    return enqueue_task ($c, $source2);
  })->then (sub {
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
      is $item1->{data}->{url}, q<https://url/item/1>;
      is $item1->{data}->{title}, q<Feed Entry 1>;
      is $item1->{data}->{desc_text}, q<This is Feed Entry 2>;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 6, name => 'copy data from another channel';

test {
  my $c = shift;
  my $urls;
  my $stream;
  my $stream2;
  my $stream3;
  my $process;
  my $process2;
  my $process3;
  my $source;
  my $source2;
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
            </rdf:Seq>
          </items>
        </channel>
        <item rdf:about="https://url/item/1.rss">
          <title>Feed Entry 1</title>
          <link>@@URL{b}@@</link>
          <description>This is Feed Entry 1</description>
          <content:encoded>
            &lt;p lang=en>This is Feed Entry 1.&lt;/p>
            &lt;p lang=ja>Kore ha Feed Entry 1 desu.&lt;/p>
          </content:encoded>
          <dc:date>2015-12-01T11:46:23+09:00</dc:date>
        </item>
      </rdf:RDF>
    }],
    b => [{'Content-Type' => 'text/xml'}, q{
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
              <rdf:li rdf:resource="https://url/item/2" />
            </rdf:Seq>
          </items>
        </channel>
        <item rdf:about="https://url/item/2.rss">
          <title>Feed Entry 2</title>
          <link>@@URL{b}@@</link>
          <description>This is Feed Entry 2</description>
          <content:encoded>
            &lt;p lang=en>This is Feed Entry 2.&lt;/p>
            &lt;p lang=ja>Kore ha Feed Entry 2 desu.&lt;/p>
          </content:encoded>
          <dc:date>2015-12-02T11:46:23+09:00</dc:date>
        </item>
      </rdf:RDF>
    }, {origin => 1}],
  })->then (sub {
    $urls = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{a}},
    );
  })->then (sub {
    $source = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{b}},
    );
  })->then (sub {
    $source2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream3 = $_[0];
    return create_sink ($c, $stream3);
  })->then (sub {
    $sink = $_[0];
    return create_process ($c, $source => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
      {name => 'rss_desc_text'},
      {name => 'fetch_item_url'},
    ] => $stream);
  })->then (sub {
    $process = $_[0];
    return create_process ($c, $source2 => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
      {name => 'rss_desc_text'},
    ] => $stream2);
  })->then (sub {
    $process2 = $_[0];
    return create_process ($c, [$stream, $stream2] => [
      {name => 'set_if_defined', fields => ['desc_text']},
    ] => $stream3, channel_map => {
      $stream2->{stream_id} => {0 => 1},
    });
  })->then (sub {
    $process3 = $_[0];
    return enqueue_task ($c, $source);
  })->then (sub {
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
      like $item1->{data}->{url}, qr</b>;
      is $item1->{data}->{title}, q<Feed Entry 1>;
      is $item1->{data}->{desc_text}, q<This is Feed Entry 2>;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 6, name => 'fetch_item_url then copy data from another channel';

test {
  my $c = shift;
  my $urls;
  my $stream;
  my $stream2;
  my $stream3;
  my $process;
  my $process2;
  my $process3;
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
            </rdf:Seq>
          </items>
        </channel>
        <item rdf:about="https://url/item/1.rss">
          <title>Feed Entry 1</title>
          <link>@@URL{b}@@</link>
          <description>This is Feed Entry 1</description>
          <content:encoded>
            &lt;p lang=en>This is Feed Entry 1.&lt;/p>
            &lt;p lang=ja>Kore ha Feed Entry 1 desu.&lt;/p>
          </content:encoded>
          <dc:date>2015-12-01T11:46:23+09:00</dc:date>
        </item>
      </rdf:RDF>
    }],
    b => [{'Content-Type' => 'text/xml'}, q{
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
              <rdf:li rdf:resource="https://url/item/2" />
            </rdf:Seq>
          </items>
        </channel>
        <item rdf:about="https://url/item/2.rss">
          <title>Feed Entry 2</title>
          <link>@@URL{b}@@</link>
          <description>This is Feed Entry 2</description>
          <content:encoded>
            &lt;p lang=en>This is Feed Entry 2.&lt;/p>
            &lt;p lang=ja>Kore ha Feed Entry 2 desu.&lt;/p>
          </content:encoded>
          <dc:date>2015-12-02T11:46:23+09:00</dc:date>
        </item>
      </rdf:RDF>
    }, {origin => 1}],
  })->then (sub {
    $urls = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{a}},
    );
  })->then (sub {
    $source = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream3 = $_[0];
    return create_sink ($c, $stream3);
  })->then (sub {
    $sink = $_[0];
    return create_process ($c, $source => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
      {name => 'rss_desc_text'},
      {name => 'fetch_item_url'},
    ] => $stream);
  })->then (sub {
    $process = $_[0];
    return create_process ($c, {origin => origin_of $urls->{b}} => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
      {name => 'rss_desc_text'},
    ] => $stream2);
  })->then (sub {
    $process2 = $_[0];
    return create_process ($c, [$stream, $stream2] => [
      {name => 'set_if_defined', fields => ['desc_text']},
    ] => $stream3, channel_map => {
      $stream2->{stream_id} => {0 => 1},
    });
  })->then (sub {
    $process3 = $_[0];
    return enqueue_task ($c, $source);
  })->then (sub {
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
      like $item1->{data}->{url}, qr</b>;
      is $item1->{data}->{title}, q<Feed Entry 1>;
      is $item1->{data}->{desc_text}, q<This is Feed Entry 2>;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 6, name => 'origin subscription';

test {
  my $c = shift;
  my $stream;
  my $process;
  my $source;
  my $sink;
  my $after = time;
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
      {name => 'STEP NOT FOUND'},
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
      is 0+@{$json->{items}}, 0;
    } $c;
    return GET ($c, qq{/process/logs?after=$after});
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 200;
      is $res->header ('Content-Type'), 'application/json; charset=utf-8';
      my $json = json_bytes2perl $res->content;
      my $items = [grep { $_->{process_id} eq $process->{process_id} } @{$json->{items}}];
      is 0+@$items, 1;
      ok $items->[0]->{timestamp};
      is $items->[0]->{error}->{process_options}, undef;
      is $items->[0]->{error}->{step}->{name}, 'STEP NOT FOUND';
      like $items->[0]->{error}->{message}, qr{\QBad step |STEP NOT FOUND|\E};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 11, name => 'process error';

test {
  my $c = shift;
  my $stream;
  my $process;
  my $source;
  my $sink;
  my $url1;
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
            </rdf:Seq>
          </items>
        </channel>
        <item rdf:about="https://url/item/1.rss">
          <title>Feed Entry 1</title>
          <link>https://url/item/@@TIME@@</link>
          <description>This is Feed Entry 1</description>
          <content:encoded>
            &lt;p lang=en>This is Feed Entry 1.&lt;/p>
            &lt;p lang=ja>Kore ha Feed Entry 1 desu.&lt;/p>
          </content:encoded>
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
    my $next_after;
    test {
      is $res->code, 200;
      is $res->header ('Content-Type'), 'application/json; charset=utf-8';
      my $json = json_bytes2perl $res->content;
      is 0+@{$json->{items}}, 1;
      my $item1 = $json->{items}->[0];
      ok $url1 = $item1->{data}->{url};
      ok $item1->{timestamp};
      ok $next_after = $json->{next_after};
      like $json->{next_url}, qr{/sink/$sink->{sink_id}/items\?after=$next_after$};
    } $c;
    return POST ($c, qq{/source/$source->{source_id}/enqueue}, {})->then (sub {
      my $res = $_[0];
      test {
        is $res->code, 202;
      } $c;
      return wait_drain $c;
    })->then (sub {
      return GET ($c, qq{/sink/$sink->{sink_id}/items?after=$next_after});
    });
  })->then (sub {
    my $res = $_[0];
    my $next_after;
    test {
      is $res->code, 200;
      is $res->header ('Content-Type'), 'application/json; charset=utf-8';
      my $json = json_bytes2perl $res->content;
      is 0+@{$json->{items}}, 1;
      my $item1 = $json->{items}->[0];
      ok $item1->{data}->{url};
      isnt $item1->{data}->{url}, $url1;
      ok $item1->{timestamp};
      ok $next_after = $json->{next_after};
      like $json->{next_url}, qr{/sink/$sink->{sink_id}/items\?after=$next_after$};
    } $c;
    return GET ($c, qq{/sink/$sink->{sink_id}/items?after=$next_after});
  })->then (sub {
    my $res = $_[0];
    my $next_after;
    test {
      is $res->code, 200;
      is $res->header ('Content-Type'), 'application/json; charset=utf-8';
      my $json = json_bytes2perl $res->content;
      is 0+@{$json->{items}}, 0;
      ok $next_after = $json->{next_after};
      like $json->{next_url}, qr{/sink/$sink->{sink_id}/items\?after=$next_after$};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 22, name => 'sink paging';

test {
  my $c = shift;
  my $stream;
  my $process;
  my $source;
  my $sink;
  my $after;
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
    $after = time;
    return POST ($c, qq{/source/$source->{source_id}/enqueue}, {});
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->code, 202;
    } $c;
    return wait_drain $c;
  })->then (sub {
    return GET ($c, qq{/sink/$sink->{sink_id}/items?after=$after});
  })->then (sub {
    my $res = $_[0];
    my $next_after;
    test {
      is $res->code, 200;
      is $res->header ('Content-Type'), 'application/json; charset=utf-8';
      my $json = json_bytes2perl $res->content;
      is 0+@{$json->{items}}, 0;
      ok $next_after = $json->{next_after};
      like $json->{next_url}, qr{/sink/$sink->{sink_id}/items\?after=$next_after$};
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 7, name => 'reprocessed but no change';

test {
  my $c = shift;
  my $urls;
  my $stream;
  my $stream2;
  my $stream3;
  my $stream4;
  my $process;
  my $process2;
  my $process3;
  my $process4;
  my $source;
  my $source2;
  my $sink;
  my $title1;
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
            </rdf:Seq>
          </items>
        </channel>
        <item rdf:about="https://url/item/1.rss">
          <title>Feed Entry 1</title>
          <link>@@URL{b}@@</link>
          <description>This is Feed Entry 1</description>
          <content:encoded>
            &lt;p lang=en>This is Feed Entry 1.&lt;/p>
            &lt;p lang=ja>Kore ha Feed Entry 1 desu.&lt;/p>
          </content:encoded>
          <dc:date>2015-12-01T11:46:23+09:00</dc:date>
        </item>
      </rdf:RDF>
    }],
    b => [{'Content-Type' => 'text/xml'}, q{
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
            </rdf:Seq>
          </items>
        </channel>
        <item rdf:about="https://url/item/1.rss">
          <title>Feed Entry 1 (@@TIME@@)</title>
          <link>@@URL{b}@@</link>
          <description>This is Feed Entry 1</description>
          <content:encoded>
            &lt;p lang=en>This is Feed Entry 1.&lt;/p>
            &lt;p lang=ja>Kore ha Feed Entry 1 desu.&lt;/p>
          </content:encoded>
          <dc:date>2015-12-01T11:46:23+09:00</dc:date>
        </item>
      </rdf:RDF>
    }],
  })->then (sub {
    $urls = $_[0];
    return create_source ($c,
      fetch => {url => $urls->{a}},
    );
  })->then (sub {
    $source = $_[0];
    return create_stream ($c);
  })->then (sub {
    return create_source ($c,
      fetch => {url => $urls->{b}},
    );
  })->then (sub {
    $source2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream2 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream3 = $_[0];
    return create_stream ($c);
  })->then (sub {
    $stream4 = $_[0];
    return create_sink ($c, $stream4);
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
    return create_process ($c, $stream => [
      {name => 'fetch_item_url'},
    ] => $stream2);
  })->then (sub {
    $process2 = $_[0];
    return create_process ($c, $source2 => [
      {name => 'httpres_to_doc'},
      {name => 'parse_rss'},
      {name => 'rss_basic'},
      {name => 'use_url_as_key'},
      {name => 'dc_date_as_timestamp'},
    ] => $stream3);
  })->then (sub {
    $process3 = $_[0];
    return create_process ($c, [$stream2, $stream3] => [
      {name => 'set_if_defined', fields => ['title']},
    ] => $stream4, channel_map => {
      $stream3->{stream_id} => {0 => 1},
    });
  })->then (sub {
    $process4 = $_[0];
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
      is $item1->{data}->{url}, $urls->{b};
      like $title1 = $item1->{data}->{title}, qr<^Feed Entry 1 \(.+\)$>;
    } $c;
  })->then (sub {
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
      is $item1->{data}->{url}, $urls->{b};
      like $item1->{data}->{title}, qr<^Feed Entry 1 \(.+\)$>;
      is $item1->{data}->{title}, $title1;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 13, name => 'stream subscripting last_updated';

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
