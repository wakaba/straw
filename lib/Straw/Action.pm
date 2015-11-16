package Straw::Action;
use strict;
use warnings;
use Promise;
use Time::HiRes qw(time);
use Digest::SHA qw(sha1_hex);
use Web::UserAgent::Functions qw(http_get);
use JSON::PS;
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

sub onlog ($;$) {
  if (@_ > 1) {
    $_[0]->{onlog} = $_[1];
  }
  return $_[0]->{onlog} ||= sub { };
} # onlog

$Straw::Step ||= {};
$Straw::ItemStep ||= {};

my $SubscriptionDelay = 3; # XXX

sub run ($$$$) {
  my ($self, $stream_id, $rule, $fetch_key) = @_;
  my $p = Promise->resolve;

  if (defined $rule->{steps} and ref $rule->{steps} eq 'ARRAY') {
    $p = $p->then (sub {
      return $self->load_for_stream ($stream_id, $rule);
    })->then (sub {
      return $self->steps ($stream_id, $rule, $fetch_key, $_[0]);
    });
  }

  $p = $p->then (sub {
    return $self->db->select ('stream_subscription', {
      src_stream_id => Dongry::Type->serialize ('text', $stream_id),
    }, fields => ['dst_stream_id'], distinct => 1)->then (sub {
      my @pid = map { $_->{dst_stream_id} } @{$_[0]->all};
      return $self->enqueue_stream_processes (\@pid, $SubscriptionDelay);
    });
  })->then (sub {
    return $self->update_subscriptions ($stream_id, $rule);
  });

  return $p;
} # run

sub load_for_export ($$) {
  my ($self, $stream_id) = @_;
  return $self->db->select ('stream_item', {
    stream_id => Dongry::Type->serialize ('text', $stream_id),
  }, order => ['timestamp', 'DESC'], limit => 1000)->then (sub { # XXXpaging
    my $out = {type => 'Stream', items => []};
    for (@{$_[0]->all}) {
      my $data = Dongry::Type->parse ('json', $_->{data});
      push @{$out->{items}}, $data;
    }
    return $out;
  });
} # load_for_export

sub load_for_stream ($$$) {
  my ($self, $stream_id, $rule) = @_;

  return Promise->resolve ({type => 'Empty'})
      unless defined $rule->{input_stream_id};

  my $out = {type => 'Stream', items => []};
  return Promise->resolve->then (sub {
    return $self->db->select ('stream_subscription', {
      src_stream_id => Dongry::Type->serialize ('text', $rule->{input_stream_id}),
      dst_stream_id => Dongry::Type->serialize ('text', $stream_id),
    }, fields => ['ref']);
  })->then (sub {
    my $data = defined $_[0] ? $_[0]->first : undef;
    my $ref = defined $data ? $data->{ref} || 0 : 0;
    $self->onlog->($self, "ref=$ref");
    return $self->db->select ('stream_item', {
      stream_id => Dongry::Type->serialize ('text', $rule->{input_stream_id}),
      updated => {'>', $ref},
    }, order => ['updated', 'ASC'], limit => 10);
  })->then (sub {
    for (@{$_[0]->all}) {
      my $data = Dongry::Type->parse ('json', $_->{data});
      push @{$out->{items}}, $data;
      $self->{loaded_stream_updated} = $_->{updated};
    }
  })->then (sub {
    return $out;
  });
} # load_for_stream

sub steps ($$$$$) {
  my ($self, $stream_id, $rule, $fetch_key, $input) = @_;
  die "Bad |steps|" unless defined $rule->{steps} and ref $rule->{steps} eq 'ARRAY';
  my @step = @{$rule->{steps}};

  unshift @step, {name => 'load_fetch_result',
                  key => $fetch_key}
      if defined $rule->{fetch} and defined $fetch_key;

  push @step, {name => 'save_stream', stream_id => $stream_id};
  my $p = Promise->resolve ($input);
  my $log = $self->onlog;
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

sub enqueue_stream_processes ($$$) {
  my ($self, $stream_ids, $delta) = @_;
  return Promise->resolve unless @$stream_ids;
  my $after = time + $delta;
  return $self->db->insert ('stream_process_queue', [map {
    +{
      stream_id => Dongry::Type->serialize ('text', $_),
      run_after => $after,
      running_since => 0,
     };
   } @$stream_ids], duplicate => 'ignore');
} # enqueue_stream_process

sub update_subscriptions ($$$) {
  my ($self, $dst_stream_id, $data) = @_;
  my $p = Promise->resolve;
  my $db = $self->db;
  my $expires = time + 60*60*24;

  my $input_id = $data->{input_stream_id};
  if (defined $input_id) {
    $p = $p->then (sub {
      return $db->insert ('stream_subscription', [{
        src_stream_id => Dongry::Type->serialize ('text', $input_id),
        dst_stream_id => Dongry::Type->serialize ('text', $dst_stream_id),
        ref => $self->{loaded_stream_updated} || 0,
        expires => $expires,
      }], duplicate => {
        ref => $db->bare_sql_fragment ('GREATEST(VALUES(ref),ref)'),
        expires => $db->bare_sql_fragment ('GREATEST(VALUES(expires),expires)'),
      });
    });
  }

  my $key;
  my $fetch = $data->{fetch};
  if (defined $fetch and ref $fetch eq 'HASH' and
      defined $fetch->{url}) {
    $p = $p->then (sub {
      my $fetch_data = perl2json_bytes_for_record $fetch;
      $key = sha1_hex $fetch_data;
      $key .= sha1_hex +Dongry::Type->serialize ('text', $fetch->{url});
      return $db->insert ('fetch', [{
        key => $key,
        data => $fetch_data,
        expires => $expires,
      }], duplicate => {
        expires => $db->bare_sql_fragment ('GREATEST(VALUES(expires),expires)'),
      })->then (sub {
        return $db->insert ('fetch_subscription', [{
          key => $key,
          dst_stream_id => Dongry::Type->serialize ('text', $dst_stream_id),
          expires => $expires,
        }], duplicate => {
          expires => $db->bare_sql_fragment ('GREATEST(VALUES(expires),expires)'),
        });
      });
    });
  }
  $p = $p->then (sub {
    return $db->update ('stream_process', {
      fetch_key => $key,
    }, where => {
      stream_id => Dongry::Type->serialize ('text', $dst_stream_id),
    });
  });

  return $p;
} # update_subscriptions

my $ProcessTimeout = 60; # XXX 60*60;

sub run_stream_processes ($) {
  my $self = $_[0];
  my $p = Promise->resolve;
  my $db = $self->db;
  my $time = time;
  return $db->update ('stream_process_queue', {
    running_since => $time,
  }, where => {
    run_after => {'<=' => $time},
    running_since => 0,
  }, limit => 10, order => ['run_after', 'asc'])->then (sub {
    return $db->select ('stream_process_queue', {
      running_since => $time,
    }, fields => ['stream_id']);
  })->then (sub {
    my @process_id = map { $_->{stream_id} } @{$_[0]->all};
    return unless @process_id;
    for my $process_id (@process_id) {
      # XXX loop detection
      $p = $p->then (sub {
        $self->onlog->($self, "Stream |$process_id|...");
        return $db->select ('stream_process', {
          stream_id => Dongry::Type->serialize ('text', $process_id),
        })->then (sub {
          my $data = $_[0]->first;
          unless (defined $data) {
            $self->onlog->($self, "Nothing to do");
            return;
          }
          my $rule = Dongry::Type->parse ('json', $data->{data});
          return $self->run ($process_id, $rule, $data->{fetch_key})->catch (sub {
            $self->onlog->($self, "Error: $_[0]");
          })->then (sub {
            $self->onlog->($self, "Done");
          });
        })->then (sub {
          return $db->delete ('stream_process_queue', {
            stream_id => Dongry::Type->serialize ('text', $process_id),
          });
        });
      }); # $p
    } # $process_id
    return undef;
  })->then (sub {
    return $db->delete ('stream_process_queue', {
      running_since => {'<', time - $ProcessTimeout, '!=' => 0},
    })->then (sub {
      return $p;
    });
  });
} # run_stream_processes

sub schedule_fetch_by_stream_id ($$) {
  my ($self, $stream_id) = @_;
  my $db = $self->db;
  return $db->select ('stream_process', {
    stream_id => Dongry::Type->serialize ('text', $stream_id),
  }, fields => ['fetch_key'])->then (sub {
    my $data = $_[0]->first;
    return unless defined $data;
    my $key = $data->{fetch_key};
    return unless defined $key;
    return $db->insert ('fetch_queue', [{
      key => $key,
      run_after => time,
      running_since => 0,
    }], duplicate => 'ignore');
  });
} # schedule_fetch_by_stream_id

sub fetch ($$$$) {
  my ($self, $key, $rule, $expires) = @_;
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    # XXX redirect
    http_get
        url => $rule->{url},
        anyevent => 1,
        cb => sub {
          $ok->($_[1]);
          # XXX 5xx, network error
        };
  })->then (sub {
    my $db = $self->db;
    return $db->insert ('fetch_result', [{
      key => Dongry::Type->serialize ('text', $key),
      data => $_[0]->as_string,
      expires => $expires,
    }], duplicate => {
      data => $db->bare_sql_fragment ('VALUES(data)'),
      expires => $db->bare_sql_fragment ('GREATEST(VALUES(expires),expires)'),
    });
  })->then (sub {
    return $self->db->select ('fetch_subscription', {
      key => Dongry::Type->serialize ('text', $key),
    }, fields => ['dst_stream_id'], distinct => 1)->then (sub {
      my @pid = map { $_->{dst_stream_id} } @{$_[0]->all};
      return $self->enqueue_stream_processes (\@pid, $SubscriptionDelay);
    });
  });
} # fetch

sub run_fetches ($) {
  my $self = $_[0];
  my $p = Promise->resolve;
  my $db = $self->db;
  my $time = time;
  return $db->update ('fetch_queue', {
    running_since => $time,
  }, where => {
    run_after => {'<=' => $time},
    running_since => 0,
  }, limit => 10, order => ['run_after', 'asc'])->then (sub {
    return $db->select ('fetch_queue', {
      running_since => $time,
    }, fields => ['key']);
  })->then (sub {
    my @process_id = map { $_->{key} } @{$_[0]->all};
    return unless @process_id;
    for my $process_id (@process_id) {
      # XXX loop detection
      $p = $p->then (sub {
        $self->onlog->($self, "Fetch |$process_id|...");
        return $db->select ('fetch', {
          key => Dongry::Type->serialize ('text', $process_id),
        })->then (sub {
          my $data = $_[0]->first;
          unless (defined $data) {
            $self->onlog->($self, "Nothing to do");
            return;
          }
          my $rule = Dongry::Type->parse ('json', $data->{data});
          return $self->fetch ($process_id, $rule, $data->{expires})->catch (sub {
            $self->onlog->($self, "Error: $_[0]");
          })->then (sub {
            $self->onlog->($self, "Done");
          });
        })->then (sub {
          return $db->delete ('fetch_queue', {
            key => Dongry::Type->serialize ('text', $process_id),
          });
        });
      }); # $p
    } # $process_id
    return undef;
  })->then (sub {
    return $db->delete ('fetch_queue', {
      running_since => {'<', time - $ProcessTimeout, '!=' => 0},
    })->then (sub {
      return $p;
    });
  });
} # run_fetches

1;
