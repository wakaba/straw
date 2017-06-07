package Straw::Worker;
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Handle;
use Promise;
use Promised::Flow;
use Dongry::Database;
use Straw::Database;
use Straw::JobScheduler;
use Straw::Fetch;
use Straw::Process;

my $ProcessInterval = $ENV{STRAW_WORKER_INTERVAL} || 60;

sub start ($) {
  my $self = bless {}, $_[0];

  $self->{db} = Dongry::Database->new (sources => $Straw::Database::Sources);

  my %stop_timer;
  my $done = 0;
  $self->{shutdown} = sub {
    $done = 1;
    for (grep { defined } values %stop_timer) {
      $_->(0);
    }
    $self->{shutdown} = sub {};
  }; # $shutdown

  my @p;
  my %run;
  my %timer;
  for my $class (qw(
    Straw::JobScheduler
    Straw::Fetch
    Straw::Process
  )) {
    my $obj = $class->new_from_db ($self->{db});
    $run{$class} = sub {
      return unless $_[0];
      return $obj->run->then (sub {
        return if $done;
        if ($_[0]) {
          return $run{$class}->(1);
        } else {
          return Promise->new (sub {
            my $done = $_[0];
            $timer{$class} = AE::timer $ProcessInterval, 0, sub {
              $done->(1);
              delete $timer{$class};
            };
            $stop_timer{$class} = $done;
          })->then ($run{$class});
        }
      });
    }; # $run{$class}
    push @p, $run{$class}->(1);
  }

  $self->{completed} = promised_cleanup {
    %run = ();
    %timer = ();
    %stop_timer = ();
  } promised_cleanup {
    return $self->{shutdown}->();
  } Promise->all (\@p);

  return Promise->resolve ($self);
} # start

sub stop ($) {
  $_[0]->{shutdown}->();
} # stop

sub completed ($) {
  return $_[0]->{completed};
} # completed

sub db ($) {
  return $_[0]->{db};
} # db

sub destroy ($) {
  my $self = $_[0];
  return Promise->all ([
    (defined $self->{db} ? $self->{db}->disconnect : undef),
  ]);
} # destroy

1;

=head1 LICENSE

Copyright 2016-2017 Wakaba <wakaba@suikawiki.org>.

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
