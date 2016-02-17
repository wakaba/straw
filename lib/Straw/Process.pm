package Straw::Process;
use strict;
use warnings;
use Time::HiRes qw(time);
use Digest::SHA qw(sha1_hex);
use JSON::PS;
use Dongry::Type;
use Straw::Fetch;
use Straw::Steps;

sub new_from_db ($$) {
  return bless {db => $_[1]}, $_[0];
} # new_from_db

sub db ($) {
  return $_[0]->{db};
} # db

sub load_process_by_id ($$) {
  my ($self, $process_id) = @_;
  return $self->db->select ('process', {
    process_id => Dongry::Type->serialize ('text', $process_id),
  })->then (sub {
    my $d = $_[0]->first;
    return undef unless defined $d;
    $d->{process_id} .= '';
    return $d;
  });
} # load_process_by_id

sub save_process ($$$) {
  my ($self, $process_id, $process_options) = @_;
  return Promise->reject ({status => 400, reason => "Bad |process_options|"})
      unless defined $process_options and ref $process_options eq 'HASH';
  my $p = Promise->resolve;
  if (defined $process_id) {
    $p = $p->then (sub {
      return $self->db->select ('process', {
        process_id => Dongry::Type->serialize ('text', $process_id),
      }, fields => ['process_id'])->then (sub {
        die {status => 404, reason => 'Process not found'}
            unless $_[0]->first;
      });
    });
  } else {
    $p = $p->then (sub {
      return $self->db->execute ('select uuid_short() as uuid', undef, source_name => 'master')->then (sub {
        $process_id = $_[0]->first->{uuid};
      });
    });
  }
  return $p->then (sub {
    return $self->db->insert ('process', [{
      process_id => Dongry::Type->serialize ('text', $process_id),
      process_options => Dongry::Type->serialize ('json', $process_options),
    }], duplicate => 'replace');
  })->then (sub {
    my $source_ids = $process_options->{input_source_ids};
    return [] unless defined $source_ids and ref $source_ids eq 'ARRAY';
    return [] unless @$source_ids;
    $source_ids = [map { Dongry::Type->serialize ('text', $_) } @$source_ids];
    return $self->db->select ('fetch_source', {
      source_id => {-in => $source_ids},
    }, fields => ['fetch_key'], distinct => 1)->then (sub {
      return [map { $_->{fetch_key} } @{$_[0]->all}];
    });
  })->then (sub {
    my $keys = $_[0];
    if (@$keys) {
      return $self->db->insert ('strict_fetch_subscription', [map { {
        fetch_key => $_,
        process_id => Dongry::Type->serialize ('text', $process_id),
      } } @$keys], duplicate => 'ignore')->then (sub {
        return $self->db->delete ('strict_fetch_subscription', {
          fetch_key => {-not_in => $keys},
          process_id => $process_id,
        });
      });
    } else {
      return $self->db->delete ('strict_fetch_subscription', {
        process_id => Dongry::Type->serialize ('text', $process_id),
      });
    }
  })->then (sub {
    my $origins = $process_options->{input_origins};
    return [] unless defined $origins and ref $origins eq 'ARRAY';
    my %found;
    return [grep { not $found{$_}++ } map { sha1_hex +Dongry::Type->serialize ('text', $_) } @$origins];
  })->then (sub {
    my $keys = $_[0];
    if (@$keys) {
      return $self->db->insert ('origin_fetch_subscription', [map { {
        origin_key => $_,
        process_id => Dongry::Type->serialize ('text', $process_id),
      } } @$keys], duplicate => 'ignore')->then (sub {
        return $self->db->delete ('origin_fetch_subscription', {
          origin_key => {-not_in => $keys},
          process_id => Dongry::Type->serialize ('text', $process_id),
        });
      });
    } else {
      return $self->db->delete ('origin_fetch_subscription', {
        process_id => Dongry::Type->serialize ('text', $process_id),
      });
    }
  })->then (sub {
    my $stream_ids = $process_options->{input_stream_ids};
    if (defined $stream_ids and ref $stream_ids eq 'ARRAY' and
        @$stream_ids) {
      $stream_ids = [map { Dongry::Type->serialize ('text', $_) } @$stream_ids];
      return $self->db->insert ('stream_subscription', [map { {
        stream_id => $_,
        process_id => Dongry::Type->serialize ('text', $process_id),
        last_updated => 0,
      } } @$stream_ids], duplicate => 'ignore')->then (sub {
        return $self->db->delete ('stream_subscription', {
          stream_id => {-not_in => $stream_ids},
          process_id => Dongry::Type->serialize ('text', $process_id),
        });
      });
    } else {
      return $self->db->delete ('stream_subscription', {
        process_id => Dongry::Type->serialize ('text', $process_id),
      });
    }
  })->then (sub {
    return ''.$process_id;
  });
} # save_process

sub run_process ($$$$$) {
  my ($self, $process_id, $process_options, $process_args, $result) = @_;
  my $current = {process_id => $process_id,
                 process_options => $process_options,
                 process_args => $process_args,
                 #input_stream_id
                 #last_updated,
                 result => $result};
  return $self->_load ($current)->then (sub {
    return $self->_steps ($current, $_[0]);
  })->then (sub {
    return $self->_save ($current, $_[0]);
  });
} # run_process

sub _load ($$) {
  my ($self, $current) = @_;

  if (defined $current->{process_args}->{fetch_key}) {
    my $fetch = Straw::Fetch->new_from_db ($self->db);
    return $fetch->load_fetch_result ($current->{process_args}->{fetch_key})->then (sub {
      die "Fetch result for |$current->{process_args}->{fetch_key}| not available"
          unless defined $_[0];
      require HTTP::Response;
      return {type => 'HTTP::Response',
              res => HTTP::Response->parse ($_[0])};
    });
  } elsif (defined $current->{process_args}->{stream_id}) {
    my $src_stream_id = $current->{process_args}->{stream_id};
    my $map = {};
    $map = $current->{process_options}->{input_channel_mappings}->{$src_stream_id}
        if defined $current->{process_options}->{input_channel_mappings} and
           ref $current->{process_options}->{input_channel_mappings} eq 'HASH';
    my $dest_stream_id = $current->{process_options}->{output_stream_id};
    $map = {} unless defined $map and ref $map eq 'HASH';
    my $items = [];
    return $self->db->select ('stream_subscription', {
      stream_id => Dongry::Type->serialize ('text', $src_stream_id),
      process_id => Dongry::Type->serialize ('text', $current->{process_id}),
    }, fields => ['last_updated'])->then (sub {
      my $d = $_[0]->first;
      my $ref = defined $d ? $d->{last_updated} : 0;
      return $self->db->select ('stream_item_data', {
        stream_id => Dongry::Type->serialize ('text', $src_stream_id),
        updated => {'>', $ref},
      }, fields => ['data', 'channel_id', 'item_key', 'updated'],
          order => ['updated', 'ASC'], limit => 10);
    })->then (sub {
      my $item_by_key = {};
      my @item_key;
      for (@{$_[0]->all}) {
        my $item;
        my $key = $_->{item_key};
        if (defined $key) {
          push @item_key, $key;
          if (defined $item_by_key->{$key}) {
            $item = $item_by_key->{$key};
          } else {
            push @$items, $item = $item_by_key->{$key} = {};
          }
        } else {
          push @$items, $item = {};
        }
        my $channel_id = 0+($map->{$_->{channel_id}} // $_->{channel_id});
        $item->{$channel_id} = Dongry::Type->parse ('json', $_->{data});
        $current->{last_updated} = $_->{updated};
      }
      return unless @item_key;
      return $self->db->select ('stream_item_data', {
        stream_id => Dongry::Type->serialize ('text', $dest_stream_id),
        item_key => {-in => \@item_key},
      }, fields => ['data', 'channel_id', 'item_key'])->then (sub {
        for (@{$_[0]->all}) {
          my $key = $_->{item_key};
          next unless defined $key;
          next unless defined $item_by_key->{$key};
          $item_by_key->{$key}->{$_->{channel_id}}
              //= Dongry::Type->parse ('json', $_->{data});
        }
        # XXX need lock?
      });
    })->then (sub {
      return {type => 'Stream', items => $items};
    });
  }

  die "Bad process argument";
} # _load

sub _steps ($$$) {
  my ($self, $current, $input) = @_;
  die "No steps defined"
      if not defined $current->{process_options}->{steps} or
         not ref $current->{process_options}->{steps} eq 'ARRAY';
  my @step = @{$current->{process_options}->{steps}};

  my $p = Promise->resolve ($input);
  for my $step (@step) {
    die "Bad step" unless ref $step eq 'HASH';
    my $step_name = $step->{name} // '';
    $p = $p->then (sub {
      my $act = $Straw::Step->{$step_name};
      if (not defined $act) {
        my $code = $Straw::ItemStep->{$step_name};
        $act = {
          in_type => 'Stream',
          code => sub {
            my ($self, $step, $input, $result) = @_;
            my $items = [];
            for my $item (@{$input->{items}}) {
              push @$items, $code->($self, $step, $item, $result); # XXX promise
              # XXX validation
            }
            return {type => 'Stream', items => $items};
          },
        } if defined $code;
      }
      die {message => "Bad step |$step_name|",
           step => $step} unless defined $act;

      my $input = $step->{input} // $_[0];
      if (not defined $input->{type} or
          not defined $act->{in_type} or
          not $act->{in_type} eq $input->{type}) {
        die "Input has different type |$input->{type}| from the expected type |$act->{in_type}|";
      }
      return $act->{code}->($self, $step, $input, $current->{result});
    });
  }
  return $p;
} # _steps

sub _save ($$$) {
  my ($self, $current, $input) = @_;

  my $stream_id = $current->{process_options}->{output_stream_id};
  die "No output stream ID" unless defined $stream_id;

  die "Input type |$input->{type}| is different from |Stream|"
      if not defined $input->{type} or not $input->{type} eq 'Stream';

  return Promise->resolve ($input) unless @{$input->{items}};
  my $updated = time;
  my @insert = (map {
    my $item = $_;
    map {
      my $d = $item->{$_};
      if (keys %{$d->{props}}) {
        my $x = {
          stream_id => Dongry::Type->serialize ('text', $stream_id),
          channel_id => $_,
          timestamp => $d->{props}->{timestamp} // $updated,
          updated => $updated,
          data => (perl2json_bytes_for_record $d),
        };
        $x->{item_key} = sha1_hex (Dongry::Type->serialize ('text', $d->{props}->{key}) // $x->{data});
        $x;
      } else {
        ();
      }
    } keys %$item;
  } reverse @{$input->{items}});
  return unless @insert;
  return $self->db->insert ('stream_item_data', \@insert, duplicate => {
    data => $self->db->bare_sql_fragment ('VALUES(data)'),
    timestamp => $self->db->bare_sql_fragment ('VALUES(timestamp)'),
    updated => $self->db->bare_sql_fragment ('if (data != values(data), VALUES(updated), updated)'),
  })->then (sub {
    return $self->db->select ('stream_subscription', {
      stream_id => Dongry::Type->serialize ('text', $stream_id),
    }, fields => ['process_id'])->then (sub {
      $current->{result}->{process} = 1;
      return $self->add_process_task
          ([map { $_->{process_id} } @{$_[0]->all}],
           stream_id => $stream_id);
    });
  })->then (sub {
    if (defined $current->{process_args}->{stream_id} and
        defined $current->{last_updated}) {
      return $self->db->update ('stream_subscription', {
        last_updated => $current->{last_updated},
      }, where => {
        stream_id => Dongry::Type->serialize ('text', $current->{process_args}->{stream_id}),
        process_id => $current->{process_id},
        last_updated => {'<', $current->{last_updated}},
      });
    }
  });
} # _save

sub add_process_task ($$;%) {
  my ($self, $process_ids, %args) = @_;
  return unless @$process_ids;
  my $process_args = perl2json_bytes_for_record
      {fetch_key => $args{fetch_key},
       stream_id => $args{stream_id}};
  my $process_args_key = sha1_hex $process_args;
  my $run_after = time + ($args{delta} || 0); # XXX duplicate vs run_after
  return $self->db->insert ('process_task', [map { {
    task_id => $self->db->bare_sql_fragment ('uuid_short ()'),
    process_id => Dongry::Type->serialize ('text', $_),
    process_args => $process_args,
    process_args_sha => $process_args_key,
    run_after => $run_after,
    running_since => 0,
  } } @$process_ids], duplicate => {
    run_after => $self->db->bare_sql_fragment ('LEAST(VALUES(run_after),run_after)'),
    running_since => 0,
  });
} # add_process_task

sub run_task ($) {
  my $self = $_[0];
  my $db = $self->db;
  my $time = time;
  my $result = {};
  return $db->execute ('call lock_process_task (:time)', {
    time => $time,
  })->then (sub {
    return $db->select ('process_task', {
      running_since => $time,
    }, fields => ['process_id', 'process_args', 'task_id'], source_name => 'master');
  })->then (sub {
    my $p = Promise->resolve (0);
    my @data = @{$_[0]->all} or return $p;
    my $process_id = $data[0]->{process_id};
    my $process_options;
    $p = $p->then (sub {
      return $self->load_process_by_id ($process_id);
    })->then (sub {
      die "Process |$process_id| not found" unless defined $_[0];
      $process_options = Dongry::Type->parse ('json', $_[0]->{process_options});
    });
    my @task_id;
    for my $data (@data) { # any $data in @data has $same $data->{process_id}
      my $args = Dongry::Type->parse ('json', $data->{process_args});
      $p = $p->then (sub {
        return $self->run_process
            ($process_id, $process_options, $args, $result);
      })->then (sub {
        return $self->error
            (process_id => $process_id,
             process_options => $process_options,
             message => 'No error');
      }, sub {
        if (ref $_[0] eq 'HASH') {
          return $self->error (%{$_[0]}, process_id => $process_id);
        } else {
          return $self->error
              (process_id => $process_id,
               process_options => $process_options,
               message => ''.$_[0]);
        }
      });
      push @task_id, $data->{task_id};
    }
    return $p->then (sub {
      $result->{continue} = 1;
      return $db->delete ('process_task', {
        task_id => {-in => \@task_id},
        #process_id => $process_id,
        #running_since => $time,
      });
    });
  })->then (sub {
    return $result;
  });
} # run_task

sub error ($%) {
  my ($self, %args) = @_;
  my $error = {message => $args{message}};
  $error->{process_options} = $args{process_options}
      if defined $args{process_options};
  $error->{step} = $args{step} if defined $args{step};
  return $self->db->insert ('process_error', [{
    process_id => Dongry::Type->serialize ('text', $args{process_id}),
    error => Dongry::Type->serialize ('json', $error),
    timestamp => time,
  }]);
} # error

sub load_error_logs ($%) {
  my ($self, %args) = @_;
  my $cond = {};
  $cond->{process_id} = $args{process_id} if defined $args{process_id};
  $cond->{timestamp} = {'>', 0+($args{after} || 0)};
  return $self->db->select ('process_error', $cond,
                            order => ['timestamp', 'asc'],
                            limit => 100)->then (sub {
    return [map {
      {
        process_id => ''.$_->{process_id},
        error => Dongry::Type->parse ('json', $_->{error}),
        timestamp => $_->{timestamp},
      };
    } @{$_[0]->all}];
  });
} # load_error_logs

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
