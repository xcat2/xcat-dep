/*  Hint file for Darwin Kernel Version 7.5.0, ncurses version of 
    libcurses.  Based in FreeBSD, ncurses hints file

    This file came from gene03@smalltime.com, September 2004.
*/

#include <ncurses.h>

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
#define C_LONG0ARGS
#undef  C_LONG2ARGS

#define C_TOUCHLINE
#define C_TOUCH3ARGS
#undef  C_TOUCH4ARGS
