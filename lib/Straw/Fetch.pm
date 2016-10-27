package Straw::Fetch;
use strict;
use warnings;
use Straw::WorkerBase;
push our @ISA, qw(Straw::WorkerBase);
use Time::HiRes qw(time);
use Digest::SHA qw(sha1_hex);
use JSON::PS;
use Dongry::Type;
use Dongry::Type::JSONPS;
use Promise;
use Web::UserAgent::Functions qw(http_get http_post);
use Wanage::URL;
use Straw::Process;
use Straw::JobScheduler;

sub main ($) {
  my $fh = shift;
  __PACKAGE__->process_main ($fh);
} # main

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
  my $origin = Wanage::URL->new_from_string ($fetch_options->{url} // '')->ascii_origin;
  $fetch_options = perl2json_bytes_for_record $fetch_options;
  my $fetch_key = sha1_hex $url;
  $fetch_key .= sha1_hex $fetch_options;
  my $origin_key;
  if (defined $origin) {
    $origin_key = sha1_hex +Dongry::Type->serialize ('text', $origin);
  }
  return ($fetch_key, $fetch_options, $origin_key);
} # serialize_fetch

sub save_fetch_source ($$$$$) {
  my ($self, $source_id, $fetch_options, $schedule_options) = @_;
  return Promise->reject ({status => 400, reason => "Bad |fetch_options|"})
      unless defined $fetch_options and ref $fetch_options eq 'HASH';
  return Promise->reject ({status => 400, reason => "Bad |schedule_options|"})
      unless defined $schedule_options and ref $schedule_options eq 'HASH';
  my $fetch_key;
  my $origin_key;
  ($fetch_key, $fetch_options, $origin_key) = serialize_fetch $fetch_options;
  my $p = Promise->resolve;
  my $old_fetch_key;
  if (defined $source_id) {
    $p = $p->then (sub {
      return $self->db->select ('fetch_source', {
        source_id => Dongry::Type->serialize ('text', $source_id),
      }, fields => ['source_id', 'fetch_key'])->then (sub {
        my $f = $_[0]->first;
        die {status => 404, reason => 'Fetch source not found'} unless $f;
        $old_fetch_key = $f->{fetch_key};
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
      origin_key => $origin_key,
      fetch_options => $fetch_options,
      schedule_options => Dongry::Type->serialize ('json', $schedule_options),
    }], duplicate => 'replace');
  })->then (sub {
    return $self->schedule_next_fetch_task ($fetch_key);
  })->then (sub {
    return $self->schedule_next_fetch_task ($old_fetch_key)
        if defined $old_fetch_key and not $fetch_key eq $old_fetch_key;
  })->then (sub {
    return ''.$source_id;
  });
} # save_fetch_source

sub add_fetch_task ($$;%) {
  my ($self, $fetch_options, %args) = @_;
  my $fetch_key;
  ($fetch_key, $fetch_options, undef) = serialize_fetch $fetch_options;
  my $after = $args{result}->{next_action_time} = time + ($args{delta} || 0);
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

sub add_fetched_task ($$$) {
  my ($self, $fetch_options, $result) = @_;
  my $fetch_key;
  ($fetch_key, undef, undef) = serialize_fetch $fetch_options;
  my ($url, $origin_key) = $self->_prepare_fetch ($fetch_options);
  return $self->_onfetch ($fetch_key, $origin_key, $result);
} # add_fetched_task

sub schedule_next_fetch_task ($$) {
  my ($self, $fetch_key) = @_;
  return $self->db->select ('fetch_source', {
    fetch_key => Dongry::Type->serialize ('text', $fetch_key),
  }, fields => ['fetch_options', 'schedule_options'])->then (sub {
    my @all = @{$_[0]->all};

    my @schedule_options = map {
      Dongry::Type->parse ('json', $_->{schedule_options});
    } @all;

    my $key = "fetch:$fetch_key";
    my $js = Straw::JobScheduler->new_from_db ($self->db);
    return $js->insert_job ($key, {
      type => 'fetch_task',
      fetch_key => $fetch_key,
      fetch_options => @all ? Dongry::Type->parse ('json', $all[0]->{fetch_options}) : {},
    }, \@schedule_options, first => 1);
  });
} # schedule_next_fetch_task

sub run_process ($) {
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
      })->then (sub {
        return $db->delete ('fetch_task', {
          fetch_key => Dongry::Type->serialize ('text', $data->{fetch_key}),
          running_since => $time,
        });
      });
    }
    return $p;
  });
} # run_process

sub _prepare_fetch ($$) {
  my ($self, $options) = @_;
  my $url = $options->{url} // '';
  $url =~ s/\{day:([+-]?[0-9]+)\}/my @t = gmtime (time + $1 * 24*60*60); sprintf '%04d-%02d-%02d', $t[5]+1900, $t[4]+1, $t[3]/ge;
  my $origin = Wanage::URL->new_from_string ($url)->ascii_origin;
  my $origin_key = defined $origin ? sha1_hex +Dongry::Type->serialize ('text', $origin) : undef;
  return ($url, $origin_key);
} # _prepare_fetch

my $HTTPTimeout = 6*50;

sub fetch ($$$$) {
  my ($self, $fetch_key, $options, $result) = @_;
  # XXX skip if fetch_result is too new and not superreload
  my ($url, $origin_key) = $self->_prepare_fetch ($options);
  my $headers = {%{$options->{headers} or {}}};
  $headers->{'User-Agent'} = 'Mozilla/5.0' unless defined $headers->{'User-Agent'};
  return Promise->resolve->then (sub {
    if (defined $options->{cookie_preflight_url}) {
      return Promise->new (sub {
        my ($ok, $ng) = @_;
        http_get
            url => $options->{cookie_preflight_url},
            header_fields => {'User-Agent' => $headers->{'User-Agent'}},
            anyevent => 1,
            timeout => $HTTPTimeout,
            cb => sub {
              if ($_[1]->code >= 590) { # network error
                $ng->($_[1]);
              } else {
                # XXX cookie parsing
                my $cookies = $_[1]->header ('Set-Cookie') || '';
                $cookies = [map { s/;.*$//; $_ } split /,/, $cookies];
                $ok->(join '; ', @$cookies);
                # XXX 4xx, 5xx
              }
            };
      });
    }
    return undef;
  })->then (sub {
    $headers->{'Cookie'} = join '; ', grep { defined $_ }
        $headers->{'Cookie'}, $_[0] if defined $_[0];
    return Promise->new (sub {
      my ($ok, $ng) = @_;
      # XXX redirect
      my $method = $options->{method} || '';
      if ($method eq 'POST') {
        http_post
            url => $url,
            header_fields => $headers,
            params => $options->{params},
            anyevent => 1,
            timeout => $HTTPTimeout,
            cb => sub {
              if ($_[1]->code >= 590) { # network error
                $ng->($_[1]);
              } else {
                $ok->($_[1]);
                # XXX 4xx, 5xx
              }
            };
      } else {
        http_get
            url => $url,
            header_fields => $headers,
            anyevent => 1,
            timeout => $HTTPTimeout,
            cb => sub {
              if ($_[1]->code >= 590) { # network error
                $ng->($_[1]);
              } else {
                $ok->($_[1]);
                # XXX 4xx, 5xx
              }
            };
      }
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
    });
  })->then (sub {
    return $self->_onfetch ($fetch_key, $origin_key, $result);
  })->then (sub {
    return $self->error
        (message => 'No error',
         fetch_key => $fetch_key,
         origin_key => $origin_key,
         fetch_options => $options);
  }, sub {
    my $error = $_[0];
    if (UNIVERSAL::isa ($error, 'HTTP::Response')) {
      return $self->error
          (message => $error->status_line,
           fetch_key => $fetch_key,
           origin_key => $origin_key,
           fetch_options => $options);
    } else {
      return $self->error
          (message => ''.$error,
           fetch_key => $fetch_key,
           origin_key => $origin_key,
           fetch_options => $options);
    }
  });
} # fetch

sub _onfetch ($$$$) {
  my ($self, $fetch_key, $origin_key, $result) = @_;
  my $process = Straw::Process->new_from_db ($self->db);
  return $self->db->select ('strict_fetch_subscription', {
    fetch_key => Dongry::Type->serialize ('text', $fetch_key),
  }, fields => ['process_id'])->then (sub {
    $result->{process} = 1;
    return $process->add_process_task
        ([map { $_->{process_id} } @{$_[0]->all}], fetch_key => $fetch_key);
  })->then (sub {
    return unless defined $origin_key;
    return $self->db->select ('origin_fetch_subscription', {
      origin_key => Dongry::Type->serialize ('text', $origin_key),
    }, fields => ['process_id'])->then (sub {
      $result->{process} = 1;
      return $process->add_process_task
          ([map { $_->{process_id} } @{$_[0]->all}],
           fetch_key => $fetch_key);
    });
  });
} # _onfetch

sub load_fetch_result ($$) {
  my ($self, $fetch_key) = @_;
  return $self->db->select ('fetch_result', {
    fetch_key => Dongry::Type->serialize ('text', $fetch_key),
  }, fields => ['fetch_options', 'result'])->then (sub {
    my $d = $_[0]->first;
    return undef unless defined $d;
    return [(json_bytes2perl $d->{fetch_options}), $d->{result}];
  });
} # load_fetch_result

sub error ($%) {
  my ($self, %args) = @_;
  my $error = {fetch_options => $args{fetch_options},
               message => $args{message}};
  return $self->db->insert ('fetch_error', [{
    fetch_key => Dongry::Type->serialize ('text', $args{fetch_key}),
    origin_key => Dongry::Type->serialize ('text', $args{origin_key}), # or undef
    error => Dongry::Type->serialize ('json', $error),
    timestamp => time,
  }]);
} # error

sub load_error_logs ($%) {
  my ($self, %args) = @_;
  my $cond = {};
  $cond->{fetch_key} = $args{fetch_key} if defined $args{fetch_key};
  $cond->{origin_key} = $args{origin_key} if defined $args{origin_key};
  $cond->{timestamp} = {'>', 0+($args{after} || 0)};
  return $self->db->select ('fetch_error', $cond,
                            order => ['timestamp', 'asc'],
                            limit => 100)->then (sub {
    return [map {
      {
        fetch_key => $_->{fetch_key},
        origin_key => $_->{origin_key},
        error => Dongry::Type->parse ('json', $_->{error}),
        timestamp => $_->{timestamp},
      };
    } @{$_[0]->all}];
  });
} # load_error_logs

sub get_source_ids_by_fetch_key ($$) {
  my ($self, $fetch_key) = @_;
  return $self->db->select ('fetch_source', {
    fetch_key => Dongry::Type->serialize ('text', $fetch_key),
  }, fields => ['source_id'])->then (sub {
    return [map { {source_id => ''.$_->{source_id}} } @{$_[0]->all}];
  });
} # get_source_ids_by_fetch_key

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
