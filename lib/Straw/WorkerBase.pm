package Straw::WorkerBase;
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Handle;
use Promise;
use Promised::Flow;
use Straw::Database;

my $ProcessInterval = $ENV{STRAW_WORKER_INTERVAL} || 60;

sub process_main ($$) {
  my $class = shift;
  my $fh = shift;

  my $db = Dongry::Database->new (sources => $Straw::Database::Sources);
  my $self = $class->new_from_db ($db);

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

  my $run; $run = sub {
    return $self->run_process->then (sub {
      return if $done;
      if ($_[0]) {
        return $run->();
      } else {
        return promised_sleep ($ProcessInterval)->then ($run);
      }
    });
  }; # $run

  (promised_cleanup {
    undef $run;
    $shutdown->();
    return $db->disconnect;
  } Promise->resolve (1)->then ($run))->to_cv->recv;

  close $fh;
} # process_main

sub new_from_db ($) {
  return bless {db => $_[1]}, $_[0];
} # new_from_db

sub db ($) {
  return $_[0]->{db};
} # db

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
