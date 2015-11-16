package Straw::Action;
use strict;
use warnings;
use Promise;
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

sub touched_stream_ids ($) {
  return $_[0]->{touched_stream_ids} ||= {};
} # touched_stream_ids

$Straw::Step ||= {};
$Straw::ItemStep ||= {};

sub run ($$$) {
  my ($self, $process_id, $rule) = @_;
  my $p = Promise->resolve;

  if (defined $rule->{fetch} and ref $rule->{fetch} eq 'HASH') {
    $p = $p->then (sub {
      return $self->fetch ($process_id, $rule->{fetch});
    });
  }

  if (defined $rule->{steps} and ref $rule->{steps} eq 'ARRAY') {
    $p = $p->then (sub {
      return $self->steps ($rule);
    });
  }

  $p = $p->then (sub {
    my $touched = [keys %{$self->touched_stream_ids}];
    return unless @$touched;
    return $self->db->select ('stream_subscription', {
      stream_id => {-in => $touched},
    }, fields => ['process_id'], distinct => 1)->then (sub {
      my @pid = map { $_->{process_id} } @{$_[0]->all};
      return unless @pid;
      my $next = time + 10;
      return $self->db->insert ('process_queue', [map {
        +{
          process_id => $_,
          run_after => $next,
          running_since => 0,
        };
      } @pid], duplicate => 'ignore');
    });
  })->then (sub {
    return $self->update_subscriptions ($process_id, $rule);
  });

  return $p;
} # run

use Web::UserAgent::Functions qw(http_get);
sub fetch ($$$) {
  my ($self, $process_id, $rule) = @_;

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
      process_id => Dongry::Type->serialize ('text', $process_id),
      data => $_[0]->as_string,
      timestamp => time,
    }], duplicate => {
      data => $db->bare_sql_fragment ('VALUES(data)'),
      timestamp => $db->bare_sql_fragment ('VALUES(timestamp)'),
    });
  });
} # fetch

sub steps ($$) {
  my ($self, $rule) = @_;
  die "Bad |steps|" unless defined $rule->{steps} and ref $rule->{steps} eq 'ARRAY';
  my @step = @{$rule->{steps}};
  my $input = {type => 'Empty'};
  if (defined $rule->{input_stream_id}) {
    $input = {type => 'StreamRef', stream_id => $rule->{input_stream_id}};
    unshift @step, {name => 'load_stream'};
  }
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

sub update_subscriptions ($$$) {
  my ($self, $process_id, $data) = @_;

  my $input_id = $data->{input_stream_id};
  return Promise->resolve unless defined $input_id;

  my $db = $self->db;
  return $db->insert ('stream_subscription', [{
    stream_id => Dongry::Type->serialize ('text', $input_id),
    process_id => Dongry::Type->serialize ('text', $process_id),
    expires => time + 60*60*24,
  }], duplicate => {
    expires => $db->bare_sql_fragment ('VALUES(expires)'),
  });
} # update_subscriptions

1;
