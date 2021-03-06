#include "hpux10-20.h"

#ifdef POSIX_SIGNALS
#undef POSIX_SIGNALS
#endif
#define POSIX_SIGNALS 1

/* SA_RESTART resets the timeout of `select', so don't use it.  */
#define BROKEN_SA_RESTART

/* It does work on HPUX to open the pty's tty in the parent (Emacs),
   then close and reopen it in the child.  */
#define USG_SUBTTY_WORKS

/* FIXME.  Peter O'Gorman reports that dumping using unexelf.o doesn't
   work either: http://debbugs.gnu.org/cgi/bugreport.cgi?bug=6811 */
#if __ia64
#define CANNOT_DUMP 1
#endif

/* arch-tag: f5a3d780-82cd-4a9a-832e-a4031aab788b
   (do not change this comment) */
