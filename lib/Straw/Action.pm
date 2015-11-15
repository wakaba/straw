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

1;
