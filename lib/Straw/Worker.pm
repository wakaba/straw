package Straw::Worker;
use strict;
use warnings;
use AnyEvent;
use Promise;
use Dongry::Database;
use Straw::Fetch;

sub new_from_db_sources ($$) {
  return bless {db_sources => $_[1]}, $_[0];
} # new_from_db

sub wait_seconds ($) {
  my $seconds = $_[0];
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    my $timer; $timer = AE::timer $seconds, 0, sub {
      $ok->();
      undef $timer;
    };
  });
} # wait_seconds

sub terminate ($) {
  $_[0]->{terminate} = 1;
} # terminate

my $SleepSeconds = 30;

sub run ($) {
  my $self = $_[0];

  # XXX concurrency
  
  my $run; $run = sub {
    my $db = Dongry::Database->new (sources => $self->{db_sources});
    my $fetch = Straw::Fetch->new_from_db ($db);
    my $r; $r = sub {
      return $fetch->run_fetch_task->then (sub {
        my $more = $_[0];
        return $r->() if $more;
      });
    }; # $r
    return Promise->resolve ($r->())->then (sub {
      return $db->disconnect;
    }, sub {
      warn $_[0]; # XXX
      return $db->disconnect;
    })->then (sub {
      undef $fetch;
      return undef $run if $self->{terminate};
      return wait_seconds ($SleepSeconds)->then ($run);
    });
  }; # $run

  return $run->();
} # run

1;
