# -*- perl -*-
use strict;
use warnings;
use Straw::Web;

$ENV{LANG} = 'C';
$ENV{TZ} = 'UTC';

return Straw::Web->psgi_app;

=head1 LICENSE

Copyright 2007-2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
