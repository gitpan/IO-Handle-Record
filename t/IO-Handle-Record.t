# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl IO-Socket-Record.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 11;
use Data::Dumper;
$Data::Dumper::Deparse=1;
BEGIN { use_ok('IO::Handle::Record') };
use IO::Socket::UNIX;
use IO::Pipe;

#########################

sub t {
  my ($got, $expected, $name)=@_;
  my $rc=($got eq $expected);
  local $_;
  ($got, $expected, $name)=map {s/\n$//;s/\n/\n#/g;$_} ($got, $expected, $name);
  print "# testing: $name\n";
  print "# expected: $expected\n";
  print "# received: $got\n";
  ok $got eq $expected, $name;
}

my ($p, $c)=(IO::Pipe->new, IO::Pipe->new);

my $pid;
while( !defined( $pid=fork ) ) {sleep 1}

if( $pid ) {
  $p->reader; $c->writer;
  my $got;

  $c->write_record( 1 );
  ($got)=$p->read_record;
  t $got, Dumper( [1] ), 'simple scalar';

  $c->write_record( 1, 2, 3, 4 );
  ($got)=$p->read_record;
  t $got, Dumper( [1, 2, 3, 4] ), 'scalar list';

  $c->write_record( [1,2], [3,4] );
  ($got)=$p->read_record;
  t $got, Dumper( [[1, 2], [3, 4]] ), 'list list';

  $c->write_record( [1,2], +{a=>'b', c=>'d'} );
  ($got)=$p->read_record;
  t $got, Dumper( [[1, 2], +{a=>'b', c=>'d'}] ), 'list+hash list';

  $c->record_opts={send_CODE=>1};
  $c->write_record( +{a=>'b', c=>'d'}, sub { $_[0]+$_[1] } );
  ($got)=$p->read_record;
  t $got, Dumper( [+{a=>'b', c=>'d'}, sub { $_[0]+$_[1] }] ), 'hash+sub list';
} else {
  $c->reader; $p->writer;
  $c->record_opts={receive_CODE=>sub {eval $_[0]}};
  while( my @l=$c->read_record ) {
    $p->write_record( Dumper( \@l ) );
  }
  exit 0;
}

($p, $c)=IO::Socket::UNIX->socketpair( AF_UNIX,SOCK_STREAM,PF_UNSPEC );
while( !defined( $pid=fork ) ) {sleep 1}

if( $pid ) {
  close $c; undef $c;
  my $got;

  $p->write_record( 1 );
  ($got)=$p->read_record;
  t $got, Dumper( [1] ), 'simple scalar';

  $p->write_record( 1, 2, 3, 4 );
  ($got)=$p->read_record;
  t $got, Dumper( [1, 2, 3, 4] ), 'scalar list';

  $p->write_record( [1,2], [3,4] );
  ($got)=$p->read_record;
  t $got, Dumper( [[1, 2], [3, 4]] ), 'list list';

  $p->write_record( [1,2], +{a=>'b', c=>'d'} );
  ($got)=$p->read_record;
  t $got, Dumper( [[1, 2], +{a=>'b', c=>'d'}] ), 'list+hash list';

  $p->record_opts={send_CODE=>1};
  $p->write_record( +{a=>'b', c=>'d'}, sub { $_[0]+$_[1] } );
  ($got)=$p->read_record;
  t $got, Dumper( [+{a=>'b', c=>'d'}, sub { $_[0]+$_[1] }] ), 'hash+sub list';
} else {
  close $p; undef $p;
  $c->record_opts={receive_CODE=>sub {eval $_[0]}};
  while( my @l=$c->read_record ) {
    $c->write_record( Dumper( \@l ) );
  }
  exit 0;
}

# Local Variables: #
# mode: cperl #
# End: #
