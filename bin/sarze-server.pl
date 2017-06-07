use strict;
use warnings;
use Path::Tiny;
use Promise;
use Sarze;
use Dongry::Database;
use Straw::Database;
use Straw::JobScheduler;

my $host = '0';
my $port = shift or die "Usage: $0 port";

Sarze->start (
  hostports => [
    [$host, $port],
  ],
  psgi_file_name => path (__FILE__)->parent->child ('server.psgi'),
  worker_background_class => 'Straw::Worker',
  max_worker_count => 2,
)->then (sub {
  my $server = $_[0];
  my @p;
  push @p, $server->completed;

  my $CleanupInterval = 60*60;
  my $db = Dongry::Database->new (sources => $Straw::Database::Sources);
  my $js = Straw::JobScheduler->new_from_db ($db);
  push @p, $js->insert_job ("Straw::Expire", {
    type => 'expire_task',
  }, [{every_seconds => $CleanupInterval}]);
  
  return Promise->all (\@p);
})->to_cv->recv;
