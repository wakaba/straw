package Straw::Fetch;
use strict;
use warnings;
use Time::HiRes qw(time);
use Digest::SHA qw(sha1_hex);
use JSON::PS;
use Dongry::Type;
use Dongry::Type::JSONPS;
use Promise;
use Web::UserAgent::Functions qw(http_get);
use Straw::Process;

sub new_from_db ($$) {
  return bless {db => $_[1]}, $_[0];
} # new_from_db

sub db ($) {
  return $_[0]->{db};
} # db

sub load_fetch_source_by_id ($$) {
  my ($self, $source_id) = @_;
  return $self->db->select ('fetch_source', {
    source_id => Dongry::Type->serialize ('text', $source_id),
  })->then (sub {
    my $data = $_[0]->first;
    return undef unless defined $data;
    $data->{source_id} .= '';
    return $data;
  });
} # load_fetch_source_by_id

sub serialize_fetch ($) {
  my $fetch_options = $_[0];
  my $url = Dongry::Type->serialize ('text', $fetch_options->{url} // '');
  $fetch_options = perl2json_bytes_for_record $fetch_options;
  my $fetch_key = sha1_hex $url;
  $fetch_key .= sha1_hex $fetch_options;
  return ($fetch_key, $fetch_options);
} # serialize_fetch

sub save_fetch_source ($$$$$) {
  my ($self, $source_id, $fetch_options, $schedule_options, $result) = @_;
  return Promise->reject ({status => 400, reason => "Bad |fetch_options|"})
      unless defined $fetch_options and ref $fetch_options eq 'HASH';
  return Promise->reject ({status => 400, reason => "Bad |schedule_options|"})
      unless defined $schedule_options and ref $schedule_options eq 'HASH';
  my $fetch_key;
  ($fetch_key, $fetch_options) = serialize_fetch $fetch_options;
  my $p = Promise->resolve;
  if (defined $source_id) {
    $p = $p->then (sub {
      return $self->db->select ('fetch_source', {
        source_id => Dongry::Type->serialize ('text', $source_id),
      }, fields => ['source_id'])->then (sub {
        die {status => 404, reason => 'Fetch source not found'}
            unless $_[0]->first;
      });
    });
  } else {
    $p = $p->then (sub {
      return $self->db->execute ('select uuid_short() as uuid', undef, source_name => 'master')->then (sub {
        $source_id = $_[0]->first->{uuid};
      });
    });
  }
  return $p->then (sub {
    return $self->db->insert ('fetch_source', [{
      source_id => Dongry::Type->serialize ('text', $source_id),
      fetch_key => $fetch_key,
      fetch_options => $fetch_options,
      schedule_options => Dongry::Type->serialize ('json', $schedule_options),
    }], duplicate => 'replace');
  })->then (sub {
    return $self->schedule_next_fetch_task ($fetch_key, $result);
  })->then (sub {
    return ''.$source_id;
  });
} # save_fetch_source

sub add_fetch_task ($$;%) {
  my ($self, $fetch_options, %args) = @_;
  my $fetch_key;
  ($fetch_key, $fetch_options) = serialize_fetch $fetch_options;
  my $after = $args{result}->{next_fetch_time} = time + ($args{delta} || 0);
  return $self->db->insert ('fetch_task', [{
    fetch_key => $fetch_key,
    fetch_options => $fetch_options,
    run_after => $after,
    running_since => 0,
  }], duplicate => {
    run_after => $self->db->bare_sql_fragment (q{LEAST(run_after, VALUES(run_after))}),
    running_since => 0,
  });
} # add_fetch_task

sub schedule_next_fetch_task ($$$) {
  my ($self, $fetch_key, $result) = @_;
  return $self->db->select ('fetch_source', {
    fetch_key => Dongry::Type->serialize ('text', $fetch_key),
  }, fields => ['fetch_options', 'schedule_options'])->then (sub {
    my @all = @{$_[0]->all};
    return undef unless @all;
    my $fetch_options = Dongry::Type->parse
        ('json', $all[0]->{fetch_options});
    my @schedule_options = map {
      Dongry::Type->parse ('json', $_->{schedule_options});
    } @all;

    my $every;
    for my $options (@schedule_options) {
      if (defined $options->{every_seconds}) {
        $every = $options->{every_seconds}
            if not defined $every or
               $every > $options->{every_seconds};
      }
    }
    return undef unless defined $every;

    $every = 1 if $every < 1;
    return $self->add_fetch_task
        ($fetch_options, delta => $every, result => $result);
  });
} # schedule_next_fetch_task

my $ProcessTimeout = 60; # XXX 60*60;

sub run_task ($) {
  my $self = $_[0];
  my $db = $self->db;
  my $time = time;
  my $result = {};
  return $db->update ('fetch_task', {
    running_since => $time,
  }, where => {
    run_after => {'<=' => $time},
    running_since => 0,
  }, limit => 1, order => ['run_after', 'asc'])->then (sub {
    return $db->select ('fetch_task', {
      running_since => $time,
    }, fields => ['fetch_key', 'fetch_options'], source_name => 'master');
  })->then (sub {
    my $p = Promise->resolve (0);
    for my $data (@{$_[0]->all}) {
      my $options = Dongry::Type->parse ('json', $data->{fetch_options});
      return $p = $p->then (sub {
        return $self->fetch ($data->{fetch_key}, $options, $result);
      })->catch (sub {
        warn $_[0]; # XXX error reporting
      })->then (sub {
        $result->{continue} = 1;
        return $db->delete ('fetch_task', {
          fetch_key => $data->{fetch_key},
          running_since => $time,
        })->then (sub {
          return $self->schedule_next_fetch_task ($data->{fetch_key}, {});
        });
      });
    }
    return $p;
  })->then (sub {
    return $db->delete ('fetch_task', {
      running_since => {'<', time - $ProcessTimeout, '!=' => 0},
    });
  })->then (sub {
    return $db->execute ('select run_after from fetch_task order by run_after asc limit 1')->then (sub {
      my $d = $_[0]->first;
      $result->{next_fetch_time} = $d->{run_after} if defined $d;
      return $result;
    }) unless $result->{continue};
    return $result;
  });
} # run_task

sub fetch ($$$$) {
  my ($self, $fetch_key, $options, $result) = @_;
  # XXX skip if fetch_result is too new
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    # XXX redirect
    http_get
        url => $options->{url},
        anyevent => 1,
        cb => sub {
          $ok->($_[1]);
          # XXX 5xx, network error
        };
  })->then (sub {
    my $db = $self->db;
    return $db->insert ('fetch_result', [{
      fetch_key => Dongry::Type->serialize ('text', $fetch_key),
      fetch_options => Dongry::Type->serialize ('json', $options),
      result => $_[0]->as_string,
      expires => time + 60*60*10,
    }], duplicate => {
      result => $db->bare_sql_fragment ('VALUES(result)'),
      expires => $db->bare_sql_fragment ('GREATEST(VALUES(expires),expires)'),
    });
  })->then (sub {
    my $process = Straw::Process->new_from_db ($self->db);
    return $self->db->select ('strict_fetch_subscription', {
      fetch_key => Dongry::Type->serialize ('text', $fetch_key),
    }, fields => ['process_id'])->then (sub {
      $result->{process} = 1;
      return $process->add_process_task
          ([map { $_->{process_id} } @{$_[0]->all}], fetch_key => $fetch_key);
    });
    # XXX origin_fetch_subscription
  });
} # fetch

sub load_fetch_result ($$) {
  my ($self, $fetch_key) = @_;
  return $self->db->select ('fetch_result', {
    fetch_key => Dongry::Type->serialize ('text', $fetch_key),
  }, fields => ['result'])->then (sub {
    my $d = $_[0]->first;
    return undef unless defined $d;
    return $d->{result};
  });
} # load_fetch_result

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
