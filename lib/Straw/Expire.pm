package Straw::Expire;
use strict;
use warnings;
use Time::HiRes qw(time);
use Promise;

sub new_from_db ($$) {
  return bless {db => $_[1]}, $_[0];
} # new_from_db

sub db ($) {
  return $_[0]->{db};
} # db

my $ExpirationWorkerSleep = 10*60;
my $FetchTimeout = 60*5;
my $ProcessTimeout = 60*60;

sub run_task ($) {
  my $self = $_[0];
  my $db = $self->db;
  return $db->delete ('process_task', {
    running_since => {'<', time - $ProcessTimeout, '!=' => 0},
  })->then (sub {
    return $db->delete ('fetch_task', {
      running_since => {'<', time - $FetchTimeout, '!=' => 0},
    });
  })->then (sub {
    return {next_action_time => time + $ExpirationWorkerSleep};
  })
} # run_task

1;
