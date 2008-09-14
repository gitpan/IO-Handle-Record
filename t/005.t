use Test::More;
use Test::Deep;
use Data::Dumper;
$Data::Dumper::Deparse=1;
use IO::Handle::Record;
use IO::Socket::UNIX;
use IO::Select;
use Errno qw/EAGAIN/;

#########################

sub check_afunix {
  my ($r, $w);
  return unless eval {
    socketpair $r, $w, AF_UNIX, SOCK_STREAM, PF_UNSPEC and
      sockaddr_family( getsockname $r ) == AF_UNIX
  };
}

if( check_afunix ) {
  plan tests=>4;
} else {
  plan skip_all=>'need a working socketpair based on AF_UNIX sockets';
}

my ($p, $c)=IO::Socket::UNIX->socketpair( AF_UNIX,SOCK_STREAM,PF_UNSPEC );
my $pid;
while( !defined( $pid=fork ) ) {select undef, undef, undef, .1}

if( $pid ) {
  close $c; undef $c;
  my $got;
  $p->blocking(0);
  my $sel=IO::Select->new($p);

  my $again=0;
  $p->fds_to_send=[map {open my($fh), $_; $fh} 'Changes', 'MANIFEST'];
  if( $sel->can_write and !$p->write_record( ('xyzabc123')x90000 ) ) {
    $again++;
    while( $sel->can_write and !$p->write_record ) {
      $again++;
    }
  }
  print "# again=$again\n";

  $p->blocking(1);
  ($got, my $filecontent)=$p->read_record;
  cmp_deeply $got, 90000, 'nonblocking write';

  cmp_deeply $again, code(sub{$_[0]>0 ? 1 : (0, "expected >0, got $_[0]")}),
             'again>0';

  cmp_deeply $filecontent, [map {local $/; my $f; open $f, $_ and scalar <$f>} 'Changes', 'MANIFEST'], 'file content';

  close $p; undef $p;
  wait;
  cmp_deeply $?, 0, 'wait for child';
} else {
  close $p; undef $p;
  select undef, undef, undef, 0.5;
  while( my @l=$c->read_record ) {
    local $/;
    $c->write_record( 0+@l, [map {scalar <$_>} @{$c->received_fds}] );
  }
  exit 0;
}

# Local Variables: #
# mode: cperl #
# End: #
