package Tests;
use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/modules/*/lib');
use File::Temp;
use AnyEvent;
use Promise;
use Promised::File;
use Promised::Plackup;
use Promised::Mysqld;
use JSON::PS;
use Web::UserAgent::Functions qw(http_post http_get);
use Test::More;
use Test::X1;

our @EXPORT;

push @EXPORT, grep { not /^\$/ } @Test::More::EXPORT, @Test::X1::EXPORT, @JSON::PS::EXPORT;

sub import ($;@) {
  my $from_class = shift;
  my ($to_class, $file, $line) = caller;
  no strict 'refs';
  for (@_ ? @_ : @{$from_class . '::EXPORT'}) {
    my $code = $from_class->can ($_)
        or die qq{"$_" is not exported by the $from_class module at $file line $line};
    *{$to_class . '::' . $_} = $code;
  }
} # import

my $MySQLServer;
my $HTTPServer;

my $root_path = path (__FILE__)->parent->parent->parent->absolute;

sub db_sqls () {
  my $file = Promised::File->new_from_path
      ($root_path->child ('db/straw.sql'));
  return $file->read_byte_string->then (sub {
    return [split /;/, $_[0]];
  });
} # db_sqls

push @EXPORT, qw(web_server);
sub web_server (;$) {
  my $web_host = $_[0];
  my $cv = AE::cv;
  my $bearer = rand;
  $MySQLServer = Promised::Mysqld->new;
  Promise->all ([
    $MySQLServer->start,
  ])->then (sub {
    my $dsn = $MySQLServer->get_dsn_string (dbname => 'straw_test');
    $MySQLServer->{_temp} = my $temp = File::Temp->newdir;
    my $temp_dir_path = path ($temp)->absolute;
    my $temp_path = $temp_dir_path->child ('file');
    my $temp_file = Promised::File->new_from_path ($temp_path);
    $HTTPServer = Promised::Plackup->new;
    $HTTPServer->set_option ('--server' => 'Twiggy::Prefork');
    $HTTPServer->envs->{APP_CONFIG} = $temp_path;
    return Promise->all ([
      db_sqls->then (sub {
        $MySQLServer->create_db_and_execute_sqls (straw_test => $_[0]);
      }),
      $temp_file->write_byte_string (perl2json_bytes +{
        alt_dsns => {master => {straw => $dsn}},
        dsns => {straw => $dsn},
      }),
    ]);
  })->then (sub {
    $HTTPServer->plackup ($root_path->child ('plackup'));
    $HTTPServer->set_option ('--host' => $web_host) if defined $web_host;
    $HTTPServer->set_option ('--app' => $root_path->child ('bin/server.psgi'));
    return $HTTPServer->start;
  })->then (sub {
    $cv->send ({host => $HTTPServer->get_host});
  });
  return $cv;
} # web_server

push @EXPORT, qw(stop_web_server);
sub stop_web_server () {
  my $cv = AE::cv;
  $cv->begin;
  for ($HTTPServer, $MySQLServer) {
    next unless defined $_;
    $cv->begin;
    $_->stop->then (sub { $cv->end });
  }
  $cv->end;
  $cv->recv;
} # stop_web_server

push @EXPORT, qw(GET);
sub GET ($$) {
  my ($c, $url) = @_;
  my $host = $c->received_data->{host};
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    http_get
        url => qq{http://$host$url},
        timeout => 60,
        anyevent => 1,
        cb => sub {
          my (undef, $res) = @_;
          $ok->($res);
        };
  });
} # GET

push @EXPORT, qw(POST);
sub POST ($$$) {
  my ($c, $url, $params) = @_;
  my $host = $c->received_data->{host};
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    http_post
        url => qq{http://$host$url},
        params => $params,
        timeout => 60,
        anyevent => 1,
        cb => sub {
          my (undef, $res) = @_;
          $ok->($res);
        };
  });
} # POST

push @EXPORT, qw(create_source);
sub create_source ($%) {
  my ($c, %args) = @_;
  $args{type} //= 'fetch_source' if defined $args{fetch};
  return POST ($c, q</source>, {
    type => $args{type},
    fetch_options => (perl2json_bytes $args{fetch}),
    schedule_options => (perl2json_bytes $args{schedule} || {}),
  })->then (sub {
    my $res = $_[0];
    die "create_source failed" unless $res->code == 200;
    return json_bytes2perl $res->content;
  });
} # create_source

1;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
