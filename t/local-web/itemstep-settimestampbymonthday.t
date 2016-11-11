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
    a => [{'Content-Type' => 'application/json'}, (perl2json_bytes [
      {month => 10, day => 2},
    ])],
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
      {name => 'httpres_to_json'},
      {name => 'extract_array_items', path => '/'},
      {name => 'set_timestamp_by_month_day',
       month_field => 'month', day_field => 'day'},
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
      is $item1->{data}->{month}, 10;
      is $item1->{data}->{day}, 2;
      ok my $t = $item1->{data}->{timestamp};
      my $d = $t - time;
      $d = -$d if $d < 0;
      ok $d < 60*60*24*200, "$d < " . 60*60*24*200;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 8, name => 'set_timestamp_by_month_day';

test {
  my $c = shift;
  my $stream;
  my $process;
  my $source;
  my $sink;
  return remote ($c, {
    a => [{'Content-Type' => 'application/json'}, (perl2json_bytes [
      {month => 10, day => 2},
    ])],
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
      {name => 'httpres_to_json'},
      {name => 'extract_array_items', path => '/'},
      {name => 'set_timestamp_by_month_day',
       month_field => 'month', day_field => 'day'},
      {name => 'set_timestamp_by_month_day',
       month_field => 'month2', day_field => 'day2'},
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
      is $item1->{data}->{month}, 10;
      is $item1->{data}->{day}, 2;
      ok my $t = $item1->{data}->{timestamp};
      my $d = $t - time;
      $d = -$d if $d < 0;
      ok $d < 60*60*24*200, "$d < " . 60*60*24*200;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 8, name => 'set_timestamp_by_month_day';

test {
  my $c = shift;
  my $stream;
  my $process;
  my $source;
  my $sink;
  return remote ($c, {
    a => [{'Content-Type' => 'application/json'}, (perl2json_bytes [
      {month => 10, day => 2, ref => 1478851520},
      {month => 3, day => 2, ref => 1478851520},
    ])],
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
      {name => 'httpres_to_json'},
      {name => 'extract_array_items', path => '/'},
      {name => 'set_timestamp_by_month_day',
       month_field => 'month', day_field => 'day', ref_field => 'ref'},
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
      my $items = [sort { $a->{data}->{timestamp} <=> $b->{data}->{timestamp} } @{$json->{items}}];
      is $items->[0]->{data}->{timestamp}, 1475366400;
      is $items->[1]->{data}->{timestamp}, 1488412800;
    } $c;
  })->then (sub { done $c; undef $c });
} wait => $wait, n => 6, name => 'set_timestamp_by_month_day';

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
