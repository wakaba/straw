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

sub main ($) {
  my $fh = shift;

  my $db = Dongry::Database->new (sources => $Straw::Database::Sources);

  my $done = 0;
  my $signals = {};
  my $shutdown = sub {
    $done = 1;
    undef $signals;
  }; # $shutdown

  for my $signal (qw(INT TERM QUIT)) {
    $signals->{$signal} = AE::signal $signal => $shutdown;
  }

  my $hdl = AnyEvent::Handle->new
      (fh => $fh,
       on_read => sub {
         while ($_[0]->{rbuf} =~ s/^([^\x0A]*)\x0A//) {
           my $line = $1;
           if ($line =~ /\Ashutdown\z/) {
             $shutdown->();
           } else {
             #XXX $wp->log ("Broken command from main process: |$line|");
           }
         }
       },
       on_eof => sub { $_[0]->destroy },
       on_error => sub { $_[0]->destroy });

  my @p;
  my %run;
  for my $class (qw(
    Straw::JobScheduler
    Straw::Fetch
    Straw::Process
  )) {
    my $self = $class->new_from_db ($db);
    $run{$class} = sub {
      return $self->run->then (sub {
        return if $done;
        if ($_[0]) {
          return $run{$class}->();
        } else {
          return promised_sleep ($ProcessInterval)->then ($run{$class});
        }
      });
    }; # $run{$class}
    push @p, $run{$class}->();
  }

  (promised_cleanup {
    %run = ();
    $shutdown->();
    return $db->disconnect;
  } Promise->all (\@p))->to_cv->recv;

  close $fh;
} # main

1;

=head1 LICENSE

Copyright 2016 Wakaba <wakaba@suikawiki.org>.

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
