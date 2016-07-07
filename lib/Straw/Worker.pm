package Straw::Worker;
use strict;
use warnings;
use AnyEvent;
use Promise;
use Web::UserAgent::Functions qw(http_post);
use Dongry::Database;
use Straw::Fetch;
use Straw::Process;
use Straw::Expire;

my $DEBUG = $ENV{WORKER_DEBUG};

sub new_from_db_sources_and_config ($$$) {
  return bless {db_sources => $_[1],
                config => $_[2],
                worker_count => {fetch => 0,
                                 process => 0,
                                 all => 0}}, $_[0];
} # new_from_db_and_config

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
    warn "Worker $type - stop (all=$self->{worker_count}->{all} $type=$self->{worker_count}->{$type})\n" if $DEBUG;
    my $db = delete $self->{db};
    return $db->disconnect;
  } elsif ($self->{worker_count}->{all} > 0) {
    if ($self->{worker_count}->{$type} > 0) {
      warn "Worker $type - stop (all=$self->{worker_count}->{all} $type=$self->{worker_count}->{$type})\n" if $DEBUG;
      return;
    } else {
      warn "Worker $type - sleep $sleep (all=$self->{worker_count}->{all} $type=$self->{worker_count}->{$type})\n" if $DEBUG;
      return wait_seconds ($sleep)->then (sub {
        return $self->run ($type);
      });
    }
  } else {
    my $db = delete $self->{db};
    return $db->disconnect->then (sub {
      warn "Worker $type - sleep (all=$self->{worker_count}->{all} $type=$self->{worker_count}->{$type})\n" if $DEBUG;
      return wait_seconds ($sleep);
    })->then (sub {
      if ($self->{terminate} and $self->{worker_count}->{all} <= 0) {
        warn "Worker $type - stop (all=$self->{worker_count}->{all} $type=$self->{worker_count}->{$type})\n" if $DEBUG;
        my $db = delete $self->{db};
        return $db->disconnect;
      } else {
        warn "Worker $type - continue (all=$self->{worker_count}->{all} $type=$self->{worker_count}->{$type})\n" if $DEBUG;
        return $self->run ($type);
      }
    });
  }
} # _after_run

sub run ($$) {
  my ($self, $type) = @_;
  return if $self->{terminate} or
            ($self->{worker_count}->{$type} || 0) + 1 > $MaxWorkers;
  $self->{worker_count}->{$type}++;
  $self->{worker_count}->{all}++;
  warn "Worker $type - start (all=$self->{worker_count}->{all} $type=$self->{worker_count}->{$type})\n" if $DEBUG;
  my $cls = {
    fetch => 'Straw::Fetch',
    process => 'Straw::Process',
    expire => 'Straw::Expire',
  }->{$type};
  my $mod = $cls->new_from_db ($self->db);
  my $after;
  my $r; $r = sub {
    $self->{active_worker_count}->{$type}++;
    $self->{active_worker_count}->{all}++;
    return $mod->run_task->then (sub {
      my $more = $_[0];
      $self->{active_worker_count}->{$type}--;
      $self->{active_worker_count}->{all}--;
      $self->run ('fetch') if $more->{fetch}; # don't return
      $self->run ('process') if $more->{process}; # don't return
      $after = $more->{next_action_time};
      return $r->() if $more->{continue};
    });
  }; # $r
  return Promise->resolve->then (sub {
    return $r->();
  })->catch (sub {
    warn $_[0];
    http_post
        url => $self->{config}->{ikachan_prefix} . '/privmsg',
        params => {
          channel => $self->{config}->{ikachan_channel},
          message => (sprintf "%s %s", __PACKAGE__, $_[0]),
          #rules => $rules,
        },
        anyevent => 1;
  })->then (sub {
    undef $mod;
    undef $r;
    return $self->_after_run ($type, $after);
  });
} # run

1;

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
