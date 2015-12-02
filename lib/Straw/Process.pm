package Straw::Process;
use strict;
use warnings;
use Digest::SHA qw(sha1_hex);
use JSON::PS;
use Dongry::Type;
use Straw::Fetch;

$Straw::Step ||= {};
$Straw::ItemStep ||= {};
use Straw::Step::Fetch;
use Straw::Step::Stream;
use Straw::Step::RSS;
use Straw::Step::HTML;
use Straw::Step::Misc;

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

#XXX edit process
sub save_process ($$) {
  my ($self, $process_options) = @_;
  return Promise->reject ({status => 400, reason => "Bad |process_options|"})
      unless defined $process_options and ref $process_options eq 'HASH';
  my $process_id;
  return $self->db->execute ('select uuid_short() as uuid', undef, source_name => 'master')->then (sub {
    $process_id = $_[0]->first->{uuid};
  })->then (sub {
    return $self->db->insert ('process', [{
      process_id => $process_id,
      process_options => Dongry::Type->serialize ('json', $process_options),
    }], duplicate => 'ignore');
  })->then (sub {
    my $source_ids = $process_options->{input_source_ids};
    return unless defined $source_ids and ref $source_ids eq 'ARRAY';
    return unless @$source_ids;
    $source_ids = [map { Dongry::Type->serialize ('text', $_) } @$source_ids];
    return $self->db->select ('fetch_source', {source_id => {-in => $source_ids}}, fields => ['fetch_key'], distinct => 1)->then (sub {
      my @key = map { $_->{fetch_key} } @{$_[0]->all};
      if (@key) {
        return $self->db->insert ('strict_fetch_subscription', [map { {
          fetch_key => $_,
          process_id => $process_id,
        } } @key], duplicate => 'ignore')->then (sub {
          return $self->db->delete ('strict_fetch_subscription', {
            fetch_key => {-not_in => \@key},
            process_id => $process_id,
          });
        });
      } else {
        return $self->db->delete ('strict_fetch_subscription', {
          process_id => $process_id,
        });
      }
    });
    # XXX origin subscription
  })->then (sub {
    return ''.$process_id;
  });
} # save_process

sub run_process ($$$) {
  my ($self, $process_options, $process_args) = @_;
  return $self->_load ($process_options, $process_args)->then (sub {
    return $self->_steps ($process_options, $_[0]);
  })->then (sub {
    return $self->_save ($process_options, $_[0]);
#XXX
#    return $self->db->select ('stream_subscription', {
#      src_stream_id => Dongry::Type->serialize ('text', $stream_id),
#    }, fields => ['dst_stream_id'], distinct => 1)->then (sub {
#      my @pid = map { $_->{dst_stream_id} } @{$_[0]->all};
#      return $self->enqueue_stream_processes (\@pid, $SubscriptionDelay);
#    });
  });
} # run_process

sub _load ($$$) {
  my ($self, $process_options, $process_args) = @_;

  if (defined $process_args->{fetch_key}) {
    my $fetch = Straw::Fetch->new_from_db ($self->db);
    return $fetch->load_fetch_result ($process_args->{fetch_key})->then (sub {
      die "Fetch result for |$process_args->{fetch_key}| not available"
          unless defined $_[0];
      require HTTP::Response;
      return {type => 'HTTP::Response',
              res => HTTP::Response->parse ($_[0])};
    });
  }

  die "No input";

=pod 

  #XXX
  my @id;
  my $out = {type => 'Stream', items => []};
  return Promise->resolve->then (sub {
    return $self->db->select ('stream_subscription', {
      src_stream_id => {-in => \@id},
      dst_stream_id => Dongry::Type->serialize ('text', $stream_id),
    }, fields => ['ref', 'src_stream_id']);
  })->then (sub {
    my $p = Promise->resolve;
    for (@{$_[0]->all}) {
      my $src = $_->{src_stream_id};
      my $ref = $_->{ref} || 0;
      $self->onlog->($self, "[$src] ref=$ref");
      $p = $p->then (sub {
        return $self->db->select ('stream_item', {
          stream_id => $src,
          updated => {'>', $ref},
        }, order => ['updated', 'ASC'], limit => 10); # XXX
      })->then (sub {
        for (@{$_[0]->all}) {
          my $data = Dongry::Type->parse ('json', $_->{data});
          push @{$out->{items}}, $data;
          $self->{loaded_stream_updated}->{$src} = $_->{updated};
        }
      });
    }
    return $p;
  })->then (sub {
    return $out;
  });

=cut

} # _load

sub _steps ($$$) {
  my ($self, $process_options, $input) = @_;
  die "No steps defined"
      if not defined $process_options->{steps} or
         not ref $process_options->{steps} eq 'ARRAY';
  my @step = @{$process_options->{steps}};

  my $p = Promise->resolve ($input);
  my $log = sub { }; # XXX$self->onlog;
  for my $step (@step) {
    die "Bad step" unless ref $step eq 'HASH';
    my $step_name = $step->{name} // '';
    $p = $p->then (sub {
      $log->($self, "$step_name...");

      my $act = $Straw::Step->{$step_name};
      if (not defined $act) {
        my $code = $Straw::ItemStep->{$step_name};
        $act = {
          in_type => 'Stream',
          code => sub {
            my $step = $_[1];
            my $items = [];
            for my $item (@{$_[2]->{items}}) {
              push @$items, $code->($item, $step); # XXX args
              # XXX validation
            }
            return {type => 'Stream', items => $items};
          },
        } if defined $code;
      }
      die "Bad step |$step_name|" unless defined $act;

      my $input = $step->{input} // $_[0];
      if (not defined $input->{type} or
          not defined $act->{in_type} or
          not $act->{in_type} eq $input->{type}) {
        die "Input has different type |$input->{type}| from the expected type |$act->{in_type}|";
      }
      return $act->{code}->($self, $step, $input);
    });
  }
  return $p;
} # steps

sub _save ($$$) {
  my ($self, $process_options, $input) = @_;

  my $stream_id = $process_options->{output_stream_id};
  die "No output stream ID" unless defined $stream_id;

  die "Input type |$input->{type}| is different from |Stream|"
      if not defined $input->{type} or not $input->{type} eq 'Stream';

  return Promise->resolve ($input) unless @{$input->{items}};
  my $updated = time;
  return $self->db->insert ('stream_item_data', [map {
    # XXX $_->{props} ? check ??
    my $timestamp = $_->{props}->{timestamp} || $updated;
    my $key = sha1_hex (Dongry::Type->serialize ('text', $_->{props}->{key} // $timestamp));
    +{
      stream_id => Dongry::Type->serialize ('text', $stream_id),
      item_key => $key,
      channel_id => 0, # XXX
      data => Dongry::Type->serialize ('json', $_),
      timestamp => $timestamp,
      updated => $updated,
    };
  } reverse @{$input->{items}}], duplicate => 'replace');
} # _save

sub add_process_task ($$;%) {
  my ($self, $process_ids, %args) = @_;
  return unless @$process_ids;
  my $process_args = perl2json_bytes {fetch_key => $args{fetch_key},
                                      stream_id => $args{stream_id}};
  my $run_after = time + ($args{delta} || 0); # XXX duplicate vs run_after
  return $self->db->insert ('process_task', [map { {
    process_id => Dongry::Type->serialize ('text', $_),
    process_args => $process_args,
    run_after => $run_after,
    running_since => 0,
  } } @$process_ids], duplicate => 'ignore');
} # add_process_task

my $ProcessTimeout = 60; # XXX 60*60;

sub run_task ($) {
  my $self = $_[0];
  my $db = $self->db;
  my $time = time;
  my $result = {};
  return $db->update ('process_task', {
    running_since => $time,
  }, where => {
    run_after => {'<=' => $time},
    running_since => 0,
  }, limit => 1, order => ['run_after', 'asc'])->then (sub {
    return $db->select ('process_task', {
      running_since => $time,
    }, fields => ['process_id', 'process_args'], source_name => 'master');
  })->then (sub {
    my $p = Promise->resolve (0);
    for my $data (@{$_[0]->all}) {
      my $args = Dongry::Type->parse ('json', $data->{process_args});
      return $p = $p->then (sub {
        return $self->load_process_by_id ($data->{process_id});
      })->then (sub {
        die "Process |$data->{process_id}| not found" unless defined $_[0];
        my $options = Dongry::Type->parse ('json', $_[0]->{process_options});
        return $self->run_process ($options, $args);
      })->catch (sub {
        warn $_[0]; # XXX error reporting
      })->then (sub {
        $result->{continue} = 1;
        return $db->delete ('process_task', {
          process_id => $data->{process_id},
        });
      });
    }
    return $p;
  })->then (sub {
    return $db->delete ('process_task', {
      running_since => {'<', time - $ProcessTimeout, '!=' => 0},
    });
  })->then (sub {
    return $result;
  });
} # run_task

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
