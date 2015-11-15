package Straw::Action;
use strict;
use warnings;
use Promise;
use Dongry::Type;
use Dongry::Type::JSONPS;
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

sub steps ($$) {
  my ($self, $steps) = @_;
  my $p = Promise->resolve ({type => 'Empty'});
  # XXX validate $steps
  my $log = $self->onlog;
  for my $step (@$steps) {
    my $step_name = $step->{name};
    $p = $p->then (sub {
      $log->($self, "$step_name...");

      my $act = $Straw::Step->{$step_name};
      if (not defined $act) {
        my $code = $Straw::ItemStep->{$step_name};
        $act = {
          in_type => 'Stream',
          code => sub {
            my $items = [];
            for my $item (@{$_[2]->{items}}) {
              push @$items, $code->($item);
              # XXX validation
            }
            return {type => 'Stream', items => $items};
          },
        };
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

sub load_stream ($$) {
  my ($self, $in) = @_;
  return Promise->reject ("Bad type |$in->{type}|")
      unless $in->{type} eq 'StreamRef';

  my $out = {type => 'Stream', items => []};
  return $self->db->select ('stream_item', {
    stream_id => Dongry::Type->serialize ('text', $in->{stream_id}),
    # XXX paging
  })->then (sub {
    for (@{$_[0]->all}) {
      push @{$out->{items}}, Dongry::Type->parse ('json', $_->{data});
    }
  })->then (sub {
    return $out;
  });
} # load_stream

1;
