package Straw::JobScheduler;
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Handle;
use Promise;
use Promised::Flow;
use Time::HiRes qw(time);
use Straw::Database;

sub new_from_db ($) {
  return bless {db => $_[1]}, $_[0];
} # new_from_db

sub db ($) {
  return $_[0]->{db};
} # db

sub insert_job ($$$;%) {
  my ($self, $key, $job, $schedule_options_list, %args) = @_;

  my $every;
  for my $options (@$schedule_options_list) {
    if (defined $options->{every_seconds}) {
      $every = $options->{every_seconds}
          if not defined $every or
             $every > $options->{every_seconds};
    }
  } # $options

  if (defined $every) {
    $every = 1 if $every < 1;
    return $self->db->insert ('job_schedule', [{
      key => Dongry::Type->serialize ('text', $key),
      job => Dongry::Type->serialize ('json', $job),
      schedule_options_list => Dongry::Type->serialize ('json', $schedule_options_list),
      next_time => time + $every,
    }], duplicate => 'replace')->then (sub {
      return $self->insert_task (time, $job) if $args{first};
    });
  } else {
    return $self->db->delete ('job_schedule', {
      key => Dongry::Type->serialize ('text', $key),
    });
  }
} # insert_job

sub run_job ($) {
  my $self = $_[0];
  ## Strictly speaking, this is racy, as there is no locking between
  ## select and insert (or delete), but insert_job is almost
  ## idempotent.
  return $self->db->select ('job_schedule', {
    next_time => {'<', time},
  }, order => ['next_time', 'asc'], limit => 1)->then (sub {
    my $f = $_[0]->first;
    return 0 unless defined $f;

    my $job = Dongry::Type->parse ('json', $f->{job});
    my $schedule_options_list = Dongry::Type->parse
        ('json', $f->{schedule_options_list});

    return $self->insert_job ($f->{key}, $job, $schedule_options_list)->then (sub {
      return $self->insert_task ($f->{next_time}, $job);
    })->then (sub { return 1 });
  });
} # run_job

sub insert_task ($$$) {
  my ($self, $run_after, $job) = @_;
  if ($job->{type} eq 'fetch_task') {
    return $self->db->insert ('fetch_task', [{
      fetch_key => Dongry::Type->serialize ('text', $job->{fetch_key}),
      fetch_options => Dongry::Type->serialize ('json', $job->{fetch_options}),
      run_after => $run_after,
      running_since => 0,
    }], duplicate => {
      run_after => $self->db->bare_sql_fragment (q{LEAST(run_after, VALUES(run_after))}),
      running_since => 0,
    });
  } else {
    die "Unknown job type |$job->{type}|";
  }
} # insert_task

my $JobInterval = $ENV{STRAW_JOB_INTERVAL} || 10;

sub process_main ($) {
  my $fh = shift;

  my $db = Dongry::Database->new (sources => $Straw::Database::Sources);
  my $self = __PACKAGE__->new_from_db ($db);

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
    return $self->run_job->then (sub {
      return if $done;
      if ($_[0]) {
        return $run->();
      } else {
        return promised_sleep ($JobInterval)->then ($run);
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
