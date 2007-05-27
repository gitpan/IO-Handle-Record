use Test::More tests => 16;
use Test::Deep;
use Data::Dumper;
$Data::Dumper::Deparse=1;
BEGIN { use_ok('IO::Handle::Record') };
use IO::Socket::UNIX;
use IO::Pipe;
use IO::Select;
use Errno qw/EAGAIN/;

#########################

sub t {
  my ($got, $expected, $name)=@_;
  my $rc=($got eq $expected);
  local $_;
  ($got, $expected, $name)=map {
    if( defined $_ ) {
      s/\n$//;s/\n/\n#/g;$_;
    } else {
      "UNDEFINED";
    }
  } ($got, $expected, $name);
  print "# testing: $name\n";
  print "# expected: $expected\n";
  print "# received: $got\n";
  ok $got eq $expected, $name;
}

my ($p, $c)=(IO::Pipe->new, IO::Pipe->new);

my $pid;
while( !defined( $pid=fork ) ) {select undef, undef, undef, .2}

if( $pid ) {
  $p->reader; $c->writer;
  my $got;

  $c->write_record( 1 );
  ($got)=$p->read_record;
  cmp_deeply $got, [1], 'simple scalar';

  $c->write_record( 'string' );
  ($got)=$p->read_record;
  cmp_deeply $got, ['string'], 'simple string';

  $c->write_record( 1, 2, 3, 4 );
  ($got)=$p->read_record;
  cmp_deeply $got, [1, 2, 3, 4], 'scalar list';

  $c->write_record( [1,2], [3,4] );
  ($got)=$p->read_record;
  cmp_deeply $got, [[1, 2], [3, 4]], 'list list';

  $c->write_record( [1,2], +{a=>'b', c=>'d'} );
  ($got)=$p->read_record;
  cmp_deeply $got, [[1, 2], +{a=>'b', c=>'d'}], 'list+hash list';

  $c->record_opts={send_CODE=>1};
  $p->record_opts={receive_CODE=>sub {eval $_[0]}};
  $c->write_record( +{a=>'b', c=>'d'}, sub { $_[0]+$_[1] } );
  ($got)=$p->read_record;
  cmp_deeply Dumper( $got ), Dumper( [+{a=>'b', c=>'d'}, sub { $_[0]+$_[1] }] ),
             'hash+sub list';
} else {
  $c->reader; $p->writer;
  $c->record_opts={receive_CODE=>sub {eval $_[0]}};
  $p->record_opts={send_CODE=>1};
  while( my @l=$c->read_record ) {
    $p->write_record( \@l  );
  }
  exit 0;
}

($p, $c)=IO::Socket::UNIX->socketpair( AF_UNIX,SOCK_STREAM,PF_UNSPEC );
while( !defined( $pid=fork ) ) {select undef, undef, undef, .1}

if( $pid ) {
  close $c; undef $c;
  my $got;

  $p->write_record( 1 );
  ($got)=$p->read_record;
  cmp_deeply $got, [1], 'simple scalar';

  $p->write_record( 1, 2, 3, 4 );
  ($got)=$p->read_record;
  cmp_deeply $got, [1, 2, 3, 4], 'scalar list';

  $p->write_record( [1,2], [3,4] );
  ($got)=$p->read_record;
  cmp_deeply $got, [[1, 2], [3, 4]], 'list list';

  $p->write_record( [1,2], +{a=>'b', c=>'d'} );
  ($got)=$p->read_record;
  cmp_deeply $got, [[1, 2], +{a=>'b', c=>'d'}], 'list+hash list';

  $p->record_opts={receive_CODE=>sub {eval $_[0]}, send_CODE=>1};
  $p->write_record( +{a=>'b', c=>'d'}, sub { $_[0]+$_[1] } );
  ($got)=$p->read_record;
  cmp_deeply Dumper( $got ), Dumper( [+{a=>'b', c=>'d'}, sub { $_[0]+$_[1] }] ),
             'hash+sub list';
} else {
  close $p; undef $p;
  $c->record_opts={receive_CODE=>sub {eval $_[0]}, send_CODE=>1};
  while( my @l=$c->read_record ) {
    $c->write_record( \@l );
  }
  exit 0;
}

($p, $c)=(IO::Pipe->new, IO::Pipe->new);
while( !defined( $pid=fork ) ) {select undef, undef, undef, .1}

if( $pid ) {
  $p->reader; $c->writer;
  my $got;
  my $msg=Storable::nfreeze( [1, 2] );
  $msg=pack( "L", length($msg) ).$msg;
  for( my $i=0; $i<length $msg; $i++ ) {
    $c->syswrite( $msg, 1, $i );
    select undef, undef, undef, 0.1;
  }
  my $again;
  ($got, $again)=$p->read_record;
  cmp_deeply $got, [1, 2], 'nonblocking read';

  cmp_deeply $again, code(sub{$_[0]>0 ? 1 : (0, "expected >0, got $_[0]")}),
             'again>0';
} else {
  $c->reader; $p->writer;
  $c->blocking(0);
  my $sel=IO::Select->new($c);

  my $again=0;
  while( $sel->can_read ) {
    $!=0;
    my @l=$c->read_record;
    if( @l ) {
      $p->write_record( \@l, $again );
    } elsif( $!==EAGAIN ) {
      $again++;
    } else {
      last;
    }
  }
  exit 0;
}

($p, $c)=(IO::Pipe->new, IO::Pipe->new);

while( !defined( $pid=fork ) ) {select undef, undef, undef, .2}

if( $pid ) {
  $p->reader; $c->writer;
  my $got;
  $c->blocking(0);
  my $sel=IO::Select->new($c);

  my $again=0;
  if( $sel->can_write and !$c->write_record( ('xyzabc123')x30000 ) ) {
    $again++;
    while( $sel->can_write and !$c->write_record ) {
      $again++;
    }
  }

  ($got)=$p->read_record;
  cmp_deeply $got, [('xyzabc123')x30000], 'nonblocking write';

  print "# again=$again\n";
  cmp_deeply $again, code(sub{$_[0]>0 ? 1 : (0, "expected >0, got $_[0]")}),
             'again>0';
} else {
  $c->reader; $p->writer;
  select undef, undef, undef, 0.5;
  while( my @l=$c->read_record ) {
    $p->write_record( \@l );
  }
  exit 0;
}

# Local Variables: #
# mode: cperl #
# End: #
