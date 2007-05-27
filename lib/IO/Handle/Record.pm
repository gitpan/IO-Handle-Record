package IO::Handle::Record;

use 5.008;
use strict;
use warnings;
use Storable;
use Class::Member::GLOB qw/record_opts read_buffer expected
			   write_buffer written/;
use Errno qw/EAGAIN EINTR/;
use Carp;

our $VERSION = '0.06';

sub read_record {
  my $I=shift;

  unless( defined $I->expected ) {
    $I->read_buffer='' unless( defined $I->read_buffer );
    my $buflen=length($I->read_buffer);
    while( $buflen<4 ) {
      my $len=$I->sysread( $I->read_buffer, 4-$buflen, $buflen );
      if( defined($len) && $len==0 ) { # EOF
	undef $I->read_buffer;
	return;
      } elsif( !defined($len) && $!==EAGAIN ) {
	return;			# non blocking file handle
      } elsif( !defined($len) && $!==EINTR ) {
	next;			# interrupted
      } elsif( !$len ) {	# ERROR
	$len=length $I->read_buffer;
	undef $I->read_buffer;
	croak "IO::Handle::Record: Protocol Error (got $len bytes, expected 4)";
      }
      $buflen+=$len;
    }
    $I->expected=unpack "L", $I->read_buffer;
    $I->read_buffer='';
  }

  my $wanted=$I->expected;
  my $buflen=length($I->read_buffer);
  while( $buflen<$wanted ) {
    my $len=$I->sysread( $I->read_buffer, $wanted-$buflen, $buflen );
    if( !defined($len) && $!==EAGAIN ) {
      return;			# non blocking file handle
    } elsif( !defined($len) && $!==EINTR ) {
      next;			# interrupted
    } elsif( !$len ) {		# EOF or ERROR
      $len=length $I->read_buffer;
      undef $I->read_buffer;
      croak "IO::Handle::Record: Protocol Error (got $len bytes, expected $wanted)";
    }
    $buflen+=$len;
  }

  my $rc=eval {
    local $Storable::Eval;
    $I->record_opts and $Storable::Eval=$I->record_opts->{receive_CODE};
    Storable::thaw( $I->read_buffer );
  };
  if( $@ ) {
    my $e=$@;
    $e=~s/ at .*//s;
    croak $e;
  }

  undef $I->expected;
  undef $I->read_buffer;

  return @{$rc};
}

sub write_record {
  my $I=shift;

  if( @_ ) {
    my $msg=eval {
      local $Storable::Deparse;
      $I->record_opts and $Storable::Deparse=$I->record_opts->{send_CODE};
      Storable::nfreeze \@_;
    };
    if( $@ ) {
      my $e=$@;
      $e=~s/ at .*//s;
      croak $e;
    }

    $I->write_buffer=pack( "L", length($msg) ).$msg;
    $I->written=0;
  }

  my $written;
  while( $I->written<length($I->write_buffer) and
	 (defined ($written=$I->syswrite( $I->write_buffer,
					  length($I->write_buffer)-$I->written,
					  $I->written)) or
	  $!==EINTR) ) {
    $I->written+=$written if( defined $written );
  }
  if( $I->written==length($I->write_buffer) ) {
    undef $I->write_buffer;
    undef $I->written;
    return 1;
  } elsif( $!==EAGAIN ) {
    return;
  } else {
    croak "IO::Handle::Record: syswrite error";
  }
}

sub read_simple_record {
  my $I=shift;
  local $/;
  my $delim;
  if( $I->record_opts ) {
    $/=$I->record_opts->{record_delimiter} || "\n";
    $delim=$I->record_opts->{field_delimiter} || "\0";
  } else {
    $/="\n";
    $delim="\0";
  }

  my $r=<$I>;
  return unless( defined $r );	# EOF

  chomp $r;
  return split /\Q$delim\E/, $r;
}

sub write_simple_record {
  my $I=shift;
  my $rdelim;
  my $delim;
  if( $I->record_opts ) {
    $rdelim=$I->record_opts->{record_delimiter} || "\n";
    $delim=$I->record_opts->{field_delimiter} || "\0";
  } else {
    $rdelim="\n";
    $delim="\0";
  }

  print( $I join( $delim , @_ ), $rdelim );
  $I->flush;
}

*IO::Handle::write_record=\&write_record;
*IO::Handle::read_record=\&read_record;
*IO::Handle::write_simple_record=\&write_simple_record;
*IO::Handle::read_simple_record=\&read_simple_record;
*IO::Handle::record_opts=\&record_opts;
*IO::Handle::expected=\&expected;
*IO::Handle::read_buffer=\&read_buffer;
*IO::Handle::written=\&written;
*IO::Handle::write_buffer=\&write_buffer;

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

=item B<$handle-E<gt>record_opts>

This lvalue method expects a hash reference with options as parameter.
The C<send_CODE> and C<receive_CODE> options are defined. They correspond
to localized versions of C<$Storable::Deparse> and C<$Storable::Eval>
respectively. See the L<Storable> manpage for further information.

Example:

 $handle->record_opts={send_CODE=>1, receive_CODE=>1};

=item B<$handle-E<gt>write_record(@data)>

writes a list of perl data structures.

C<write_record> returns 1 if the record has been transmitted. C<undef> is
returned if C<$handle> is non blocking and a EAGAIN condition is met. In
this case reinvoke the operation without parameters
(just C<$handle-E<gt>write_record>) when the handle becomes ready.
Otherwise it throws an exception C<IO::Handle::Record: syswrite error>.
Check C<$!> in this case.

EINTR is handled internally.

Example:

 $handle->write_record( [1,2],
                        sub {$_[0]+$_[1]},
                        { list=>[1,2,3],
                          hash=>{a=>'b'},
                          code=>sub {print "test\n";} } );

=item B<@data=$handle-E<gt>read_record>

reads one record of perl data structures.

On success it returns the record as list. An empty list is returned if
C<$handle> is in non blocking mode and not enough data has been read.
Check $!==EAGAIN to catch this condition. When the handle becomes ready
just repeat the operation to read the next data chunk. If a complete record
has arrived it is returned.

On EOF an empty list is returned. To distinguish this from the non blocking
empty list return set C<$!=0> before the operation and check for C<$!==EAGAIN>
after.

EINTR is handled internally.

Example:

 ($array, $sub, $hash)=$handle->read_record;

=item B<$handle-E<gt>read_buffer>
=item B<$handle-E<gt>expected>
=item B<$handle-E<gt>write_buffer>
=item B<$handle-E<gt>written>

these methods are used internally to provide a read and write buffer for
non blocking operations.

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
