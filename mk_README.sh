#!/bin/bash

(perldoc -tU ./lib/IO/Handle/Record.pm
 perldoc -tU $0
) >README

exit 0

=head1 INSTALLATION

 perl Makefile.PL
 make
 make test
 make install

=head1 DEPENDENCIES

=over 4

=item *

perl 5.8.0

=item *

Storable 2.05

=item *

Class::Member 1.3

=back

=cut