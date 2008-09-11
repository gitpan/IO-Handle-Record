#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/*
 * this code is mostly borrowed from Michael J.Pomraning's
 * Socket::MsgHdr (0.01)
 */

#include <limits.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <fcntl.h>

typedef PerlIO* InOutStream;
typedef int SysRet;

#ifndef PerlIO
#define PerlIO_fileno(f) fileno(f)
#endif

static Size_t aligned_cmsghdr_sz = 0;

struct Socket__MsgHdr {
    struct msghdr m;
    struct iovec io;
};

static void
hv_2msghdr(struct Socket__MsgHdr *mh, SV *thing)
{
    HV*     hash;
    SV **   svp;
    STRLEN  dlen;

    hash = (HV*) SvRV(thing);

    Zero(mh, 1, struct Socket__MsgHdr);

    mh->m.msg_iov    = &mh->io;
    mh->m.msg_iovlen = 1;

    if ((svp = hv_fetch(hash, "name", 4, FALSE)) && SvOK(*svp)) {
        mh->m.msg_name    = SvPV_force(*svp, dlen);
        mh->m.msg_namelen = dlen;
    }

    if ((svp = hv_fetch(hash, "buf", 3, FALSE)) && SvOK(*svp)) {
        mh->io.iov_base = SvPV_force(*svp, dlen);
        mh->io.iov_len  = dlen;
    }

    if ((svp = hv_fetch(hash, "control", 7, FALSE)) && SvOK(*svp)) {
        mh->m.msg_control    = SvPV_force(*svp, dlen);
        mh->m.msg_controllen = dlen;
    }

    if ((svp = hv_fetch(hash, "flags", 5, FALSE)) && SvOK(*svp)) {
        mh->m.msg_flags    = SvIV(*svp);
    }
}

static int
fdtype(int fd) {
  struct stat buf;
  if( fstat(fd, &buf)<0 ) return -1;
  return (buf.st_mode & S_IFMT);
}

static int
socket_family(int fd) {
  union {
    struct sockaddr sa;
    char data[PATH_MAX+sizeof(uint8_t)+sizeof(sa_family_t)];
  } un;
  socklen_t len;

  len=sizeof(un);
  if( getsockname(fd, &un.sa, &len)<0 ) return -1;
  return un.sa.sa_family;
}

MODULE = IO::Handle::Record    PACKAGE = IO::Handle::Record   PREFIX = smh_

int
smh_issock(s)
    InOutStream s;
PROTOTYPE: $
PPCODE:
{
  PERL_UNUSED_VAR(RETVAL);
  PERL_UNUSED_VAR(targ);
  if( fdtype(PerlIO_fileno(s))==S_IFSOCK ) {
    XSRETURN_YES;
  } else {
    XSRETURN_UNDEF;
  }
}

char *
smh_typeof(fd)
    int fd;
PROTOTYPE: $
CODE:
{
  switch(fdtype(fd)) {
  case S_IFSOCK:
    switch(socket_family(fd)) {
    case AF_UNIX:
      RETVAL=("IO::Socket::UNIX");
      break;
    case AF_INET:
      RETVAL=("IO::Socket::INET");
      break;
    case AF_INET6:
      RETVAL=("IO::Socket::INET6");
      break;
    default:
      RETVAL=("IO::Handle");
      break;
    }
    break;
  case S_IFREG:
    RETVAL=("IO::File");
    break;
  case S_IFDIR:
    RETVAL=("IO::Dir");
    break;
  case S_IFIFO:
    RETVAL=("IO::Pipe");
    break;
  default:
    RETVAL=("IO::Handle");
    break;
  }
}
OUTPUT:
RETVAL

SysRet
smh_sendmsg(s, msg_hdr, flags = 0)
    InOutStream s;
    SV * msg_hdr;
    int flags;

    PROTOTYPE: $$;$
    PREINIT:
    struct Socket__MsgHdr mh;
    CODE:
    hv_2msghdr(&mh, msg_hdr);
    if ((RETVAL = sendmsg(PerlIO_fileno(s), &mh.m, flags)) < 0 ) 
      XSRETURN_UNDEF;
    OUTPUT:
    RETVAL

SysRet
smh_recvmsg(s, msg_hdr, flags = 0)
    InOutStream s;
    SV * msg_hdr;
    int flags;

    PROTOTYPE: $$;$
    PREINIT:
    struct Socket__MsgHdr mh;
        
    CODE:
    hv_2msghdr(&mh, msg_hdr);
    if ((RETVAL = recvmsg(PerlIO_fileno(s), &mh.m, flags)) >= 0) {
        SV**    svp;
        HV*     hsh;

        hsh = (HV*) SvRV(msg_hdr);

        if ((svp = hv_fetch(hsh, "name", 7, FALSE)) && SvOK(*svp))
            SvCUR_set(*svp, mh.m.msg_namelen);
	if ((svp = hv_fetch(hsh, "buf", 3, FALSE)) && SvOK(*svp))
            SvCUR_set(*svp, RETVAL);
	if ((svp = hv_fetch(hsh, "control", 7, FALSE)) && SvOK(*svp))
            SvCUR_set(*svp, mh.m.msg_controllen);
    } else {
      XSRETURN_UNDEF;
    }
    OUTPUT:
    RETVAL

MODULE = IO::Handle::Record    PACKAGE = IO::Handle::Record::MsgHdr   PREFIX = smh_

SV *
smh_pack_cmsghdr(...)
    PROTOTYPE: $$$;@
    PREINIT:
        STRLEN len;
        STRLEN space;
        I32 i;
        struct cmsghdr *cm;
    CODE:
        space = 0;
        for (i=0; i<items; i+=3) {
            len = sv_len(ST(i+2));
            space += CMSG_SPACE(len);
        }
        RETVAL = newSV( space );
        SvPOK_on(RETVAL);
        SvCUR_set(RETVAL, space);

        cm = (struct cmsghdr *)SvPVX(RETVAL);
        
        for (i=0; i<items; i+=3) {
            len = sv_len(ST(i+2));
            cm->cmsg_len = CMSG_LEN(len);
            cm->cmsg_level = SvIV( ST(i) );
            cm->cmsg_type = SvIV( ST(i+1) );
            Copy(SvPVX(ST(i+2)), CMSG_DATA(cm), len, U8);
            cm = (struct cmsghdr *)((U8 *)cm + CMSG_SPACE( len ));
        }
    OUTPUT:
    RETVAL

void
smh_unpack_cmsghdr(cmsv)
    SV*     cmsv;
    INIT:
    struct msghdr dummy;
    struct cmsghdr *cm;
    STRLEN  len;
    PPCODE:
    dummy.msg_control    = (struct cmsghdr *) SvPV(cmsv, len);
    dummy.msg_controllen = len;

    if (!len)
        XSRETURN_EMPTY;

    cm = CMSG_FIRSTHDR(&dummy);
    for (; cm; cm = CMSG_NXTHDR(&dummy, cm)) {
       XPUSHs(sv_2mortal(newSViv(cm->cmsg_level)));
       XPUSHs(sv_2mortal(newSViv(cm->cmsg_type)));
       if( cm->cmsg_level==SOL_SOCKET && cm->cmsg_type==SCM_RIGHTS ) {
	 int *fdptr=(int*)CMSG_DATA(cm);
	 int nfds=(cm->cmsg_len - aligned_cmsghdr_sz)/sizeof(int);
	 int i;
	 AV *av=newAV();
	 av_extend(av, nfds);
	 for( i=0; i<nfds; i++ ) {
	   int flags=fcntl(fdptr[i], F_GETFL, 0);
	   
	   AV *inner_av=newAV();
	   av_extend(inner_av, 2);
	   av_store(inner_av, 0, newSViv(fdptr[i]));
	   av_store(inner_av, 1, newSViv(flags));
	   av_store(av, i, sv_2mortal(newRV_inc((SV*)inner_av)));
	 }
	 XPUSHs(sv_2mortal(newRV_inc((SV*)av)));
       } else {
	 XPUSHs(sv_2mortal(newSVpvn((char*)CMSG_DATA(cm),
				    (cm->cmsg_len - aligned_cmsghdr_sz))));
       }
    }

MODULE = IO::Handle::Record    PACKAGE = IO::Handle::Record   PREFIX = smh_

BOOT:
    aligned_cmsghdr_sz = CMSG_LEN(0);
