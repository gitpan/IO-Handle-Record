package IO::Handle::Record;

use 5.008;
use strict;
use warnings;
use Storable;
use Class::Member::GLOB qw/record_opts/;

our $VERSION = '0.03';

sub read_record {
  my $I=shift;
  my $buf='';
  my $len=$I->sysread( $buf, 4 );
  return if( $len==0 );			# EOF: ok
  die "IO::Handle::Record: Protocol Error (got $len bytes, expected 4)"
    unless( $len==4 );
  $len=unpack "L", $buf;
  $buf='';
  my ($buflen,$x)=(0);
  while( defined($x=$I->sysread( $buf, $len-$buflen, $buflen )) ) {
	$buflen+=$x;
	last if( $buflen>=$len );
  }
  die "IO::Handle::Record: Protocol Error (got $buflen bytes, expected $len)"
	unless( $buflen==$len );
  local $Storable::Eval;
  $I->record_opts and $Storable::Eval=$I->record_opts->{receive_CODE};
  return @{Storable::thaw( $buf )};
}

sub write_record {
  my $I=shift;
  local $Storable::Deparse;
  $I->record_opts and $Storable::Deparse=$I->record_opts->{send_CODE};
  my $msg=Storable::nfreeze \@_;
  $I->print( pack( "L", length($msg) ), $msg );
  $I->flush;
}

*IO::Handle::write_record=\&write_record;
*IO::Handle::read_record=\&read_record;
*IO::Handle::record_opts=\&record_opts;

1;
__END__

=head1 NAME

IO::Handle::Record - IO::Handle extension to pass perl data structures

=head1 SYNOPSIS

 use IO::Socket::UNIX;
 use IO::Handle::Record;

 ($p, $c)=IO::Socket::UNIX->socketpair( AF_UNIX,
                                        SOCK_STREAM,
                                        PF_UNSPEC );
 while( !defined( $pid=fork ) ) {sleep 1}

 if( $pid ) {
   close $c; undef $c;
 
   $p->record_opts={send_CODE=>1};
   $p->write_record( {a=>'b', c=>'d'},
                     sub { $_[0]+$_[1] },
                     [qw/this is a test/] );
 } else {
   close $p; undef $p;
 
   $c->record_opts={receive_CODE=>sub {eval $_[0]}};
   ($hashref, $coderef, $arrayref)=$c->read_record;
 }

=head1 DESCRIPTION

C<IO::Handle::Record> extends the C<IO::Handle> class.
Since many classes derive from C<IO::Handle> these extensions can be used
with C<IO::File>, C<IO::Socket>, C<IO::Pipe>, etc.

The methods provided read and write lists of perl data structures. They can
pass anything that can be serialized with C<Storable> even subroutines
between processes.

The following methods are added:

=over 4

=item B<record_opts>

This lvalue method expects a hash reference with options as parameter.
The C<send_CODE> and C<receive_CODE> options are defined. They correspond
to localized versions of C<$Storable::Deparse> and C<$Storable::Eval>
respectively. See the L<Storable> manpage for further information.

Example:

 $handle->record_opts={send_CODE=>1, receive_CODE=>1};

=item B<write_record>

writes a list of perl data structures.

Example:

 $handle->write_record( [1,2],
                        sub {$_[0]+$_[1]},
                        { list=>[1,2,3],
                          hash=>{a=>'b'},
                          code=>sub {print "test\n";} } );

=item B<read_record>

reads one record of perl data structures. Returns the list.

Example:

 ($array, $sub, $hash)=$handle->read_record;

=back

=head2 EXPORT

None.

=head1 SEE ALSO

C<IO::Handle>

=head1 AUTHOR

Torsten Foertsch, E<lt>torsten.foertsch@gmx.net<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Torsten Foertsch

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


=cut
