use Test::More tests => 2;
use Test::Deep;
use Data::Dumper;
$Data::Dumper::Deparse=1;
use IO::Handle::Record;
use IO::Pipe;
use IO::Select;
use Errno qw/EAGAIN/;

#########################

my ($p, $c)=(IO::Pipe->new, IO::Pipe->new);
my $pid;
while( !defined( $pid=fork ) ) {select undef, undef, undef, .1}

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
