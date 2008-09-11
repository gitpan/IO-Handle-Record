use Test::More tests => 7;
use Test::Deep;
use Data::Dumper;
$Data::Dumper::Deparse=1;
BEGIN { use_ok('IO::Handle::Record') };
use IO::Pipe;
use IO::Select;
use Errno qw/EAGAIN/;

#########################

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

# Local Variables: #
# mode: cperl #
# End: #
