/*  Hint file for the darwin platform.
 *
 *  If this configuration doesn't work, look at the file "c-none.h"
 *  for how to set the configuration options.
 */

/* These hints thanks to Scott Dietrich <sdietrich@emlab.com> */

#include <curses.h>

#ifdef C_PANELSUPPORT
#include <panel.h>
#endif

#ifdef C_MENUSUPPORT
#include <menu.h>
#endif

#ifdef C_FORMSUPPORT
#include <form.h>
#endif

#define C_LONGNAME
#undef  C_LONG0ARGS
#define C_LONG2ARGS

#define C_TOUCHLINE
#undef  C_TOUCH3ARGS
#define C_TOUCH4ARGS
