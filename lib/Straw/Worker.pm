package Straw::Worker;
use strict;
use warnings;
use AnyEvent;
use Promise;
use Dongry::Database;
use Straw::Fetch;
use Straw::Process;

sub new_from_db_sources ($$) {
  return bless {db_sources => $_[1],
                worker_count => {fetch => 0,
                                 process => 0,
                                 all => 0}}, $_[0];
} # new_from_db

sub db ($) {
  my $self = $_[0];
  return $self->{db} ||= Dongry::Database->new
      (sources => $self->{db_sources});
} # db

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
my $MaxWorkers = 5;

sub _after_run ($$$) {
  my ($self, $type, $after) = @_;
  $self->{worker_count}->{$type}--;
  $self->{worker_count}->{all}--;
  my $sleep = $SleepSeconds;
  if (defined $after and $after < time + $sleep) {
    $sleep = $after - time;
    $sleep = 1 if $sleep < 1;
  }
  if ($self->{terminate} and $self->{worker_count}->{all} <= 0) {
    my $db = delete $self->{db};
    return $db->disconnect;
  } elsif ($self->{worker_count}->{all} > 0) {
    if ($self->{worker_count}->{$type} > 0) {
      return;
    } else {
      return wait_seconds ($sleep)->then (sub {
        return $self->run ($type);
      });
    }
  } else {
    my $db = delete $self->{db};
    return $db->disconnect->then (sub {
      return wait_seconds ($sleep);
    })->then (sub {
      if ($self->{terminate} and $self->{worker_count}->{all} <= 0) {
        my $db = delete $self->{db};
        return $db->disconnect;
      } else {
        return $self->run ($type);
      }
    });
  }
} # _after_run

sub run ($$) {
  my ($self, $type) = @_;
  return if $self->{terminate} or
            $self->{worker_count}->{$type} + 1 > $MaxWorkers;
  $self->{worker_count}->{$type}++;
  $self->{worker_count}->{all}++;
  my $cls = $type eq 'fetch' ? 'Straw::Fetch' : 'Straw::Process';
  my $mod = $cls->new_from_db ($self->db);
  my $after;
  my $r; $r = sub {
    $self->{active_worker_count}->{$type}++;
    $self->{active_worker_count}->{all}++;
    return $mod->run_task->then (sub {
      my $more = $_[0];
      $self->{active_worker_count}->{$type}--;
      $self->{active_worker_count}->{all}--;
      $self->run ('process') if $more->{process}; # don't return
      $after = $more->{next_fetch_time};
      return $r->() if $more->{continue};
    });
  }; # $r
  return Promise->resolve ($r->())->catch (sub {
    warn $_[0]; # XXX
  })->then (sub {
    undef $mod;
    undef $r;
    return $self->_after_run ($type, $after);
  });
} # run

1;

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
