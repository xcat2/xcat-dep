!!  Note 1: "void *" declarations are always set to zero.
!!  Note 2: "void *"s meant to handle real pointers were made "{cast} char *".
!!  Note 3: "{out}{amp} <decl> <var>" were all originally "decl *var".
!!  Note 4: "{cast}"ing a function is usually to shut up the compiler
!!          complaining about discarding const from pointer.
!!  Note 5: Some insane curses return "char *" for standout()/standend().
!!          I don't feel like handling it, hence the "{cast}".
!
/* curs_addch */

> int {mvw}addch(chtype ch);
> int {w}echochar(chtype ch);

/* curs_addchstr */

> int {mvw}addchstr(const chtype *str);
> int {mvw}addchnstr(const chtype *str, int n);

/* curs_addstr */

> int {mvw}addstr(const char *str);
> int {mvw}addnstr(const char *str, int n);

/* curs_attr */

> int {w}attroff(int attrs);
> int {w}attron(int attrs);
> int {w}attrset(int attrs);
> {cast} int {w}standend(void);
> {cast} int {w}standout(void);
> int {w}attr_get({out}{amp} attr_t attrs, {out}{amp} short color, void *opts);
> int {w}attr_off(attr_t attrs, void *opts);
> int {w}attr_on(attr_t attrs, void *opts);
> int {w}attr_set(attr_t attrs, short color, void *opts);
> int {mvw}chgat(int n, attr_t attrs, short color, \
		 const void *opts);
> int COLOR_PAIR(int n);
> int PAIR_NUMBER(int attrs);

/* curs_beep */

> int beep(void);
> int flash(void);

/* curs_bkgd */

> int {w}bkgd(chtype ch);
> void {w}bkgdset(chtype ch);
> chtype <w>getbkgd(void);

/* curs_border */

> int {w}border(chtype ls, chtype rs_, chtype ts, chtype bs, \
		chtype tl, chtype tr, chtype bl, chtype br);
> int <w>box(chtype verch, chtype horch);
> int {mvw}hline(chtype ch, int n);
> int {mvw}vline(chtype ch, int n);

/* curs_clear */

> int {w}erase(void);
> int {w}clear(void);
> int {w}clrtobot(void);
> int {w}clrtoeol(void);

/* curs_color */

> int start_color(void);
> int init_pair(short pair, short f, short b);
> int init_color(short color, short r, short g, short b);
> bool has_colors(void);
> bool can_change_color(void);
> int color_content(short color, {out}{amp} short r, {out}{amp} short g, \
			{out}{amp} short b);
> int pair_content(short pair, {out}{amp} short f, {out}{amp} short b);

/* curs_delch */

> int {mvw}delch(void);

/* curs_deleteln */

> int {w}deleteln(void);
> int {w}insdelln(int n);
> int {w}insertln(void);

/* curs_getch */

> chtype {mvw}getch(void);
> int ungetch(chtype ch);
> int has_key(int ch);
> chtype KEY_F(int n);

/* curs_getstr */

> int {mvw}getstr({b=250}{out} char *str);
> int {mvw}getnstr({b=n+1}{out} char *str, {shift=-1} int n);

/* curs_getyx */

> void <w>getyx({out} int y, {out} int x);
> void <w>getparyx({out} int y, {out} int x);
> void <w>getbegyx({out} int y, {out} int x);
> void <w>getmaxyx({out} int y, {out} int x);

/* curs_inch */

> chtype {mvw}inch(void);

/* curs_inchstr */

> int {mvw}inchstr({b=250}{out} chtype *str);
> int {mvw}inchnstr({b=n+1}{out} chtype *str, {shift=-1} int n);

/* curs_initscr */

> WINDOW *initscr(void);
> int endwin(void);
> int isendwin(void);
> SCREEN *newterm({opt} char *type, FILE *outfd, FILE *infd);
> SCREEN *set_term(SCREEN *new);
> void delscreen(SCREEN *sp);

/* curs_inopts */

#ifdef C_INTCBREAK
> {itest} int cbreak(void);
#else
> {dup} void cbreak(void);
#endif
#ifdef C_INTNOCBREAK
> {itest} int nocbreak(void);
#else
> {dup} void nocbreak(void);
#endif
#ifdef C_INTECHO
> {itest} int echo(void);
#else
> {dup} void echo(void);
#endif
#ifdef C_INTNOECHO
> {itest} int noecho(void);
#else
> {dup} void noecho(void);
#endif
> int halfdelay(int tenths);
> int <w>intrflush(bool bf);
> int <w>keypad(bool bf);
> int <w>meta(bool bf);
> int <w>nodelay(bool bf);
> int <w>notimeout(bool bf);
#ifdef C_INTRAW
> {itest} int raw(void);
#else
> {dup} void raw(void);
#endif
#ifdef C_INTNORAW
> {itest} int noraw(void);
#else
> {dup} void noraw(void);
#endif
> void qiflush(void);
> void noqiflush(void);
> void {w}timeout(int delay);
> int typeahead(int fd);

/* curs_insch */

> int {mvw}insch(chtype ch);

/* curs_insstr */

> int {mvw}insstr(const char *str);
> int {mvw}insnstr(const char *str, int n);

/* curs_instr */

> int {mvw}instr({b=250}{out} char *str);
> int {mvw}innstr({b=n+1}{out} char *str, {shift=-1} int n);

/* curs_kernel */

> int def_prog_mode(void);
> int def_shell_mode(void);
> int reset_prog_mode(void);
> int reset_shell_mode(void);
> int resetty(void);
> int savetty(void);
#ifdef C_INTGETSYX
> {itest} int getsyx({out} int y, {out} int x);
#else
> {dup} void getsyx({out} int y, {out} int x);
#endif
#ifdef C_INTSETSYX
> {itest} int setsyx(int y, int x);
#else
> {dup} void setsyx(int y, int x);
#endif
> int curs_set(int visibility);
> int napms(int ms);

/* curs_move */

> int {w}move(int y, int x);

/* curs_outopts */

> int <w>clearok(bool bf);
#ifdef C_INTIDLOK
> {itest} int <w>idlok(bool bf);
#else
> {dup} void <w>idlok(bool bf);
#endif
> void <w>idcok(bool bf);
> void <w>immedok(bool bf);
> int <w>leaveok(bool bf);
> int {w}setscrreg(int top, int bot);
> int <w>scrollok(bool bf);
#ifdef C_INTNL
> {itest} int nl(void);
#else
> {dup} void nl(void);
#endif
#ifdef C_INTNONL
> {itest} int nonl(void);
#else
> {dup} void nonl(void);
#endif

/* curs_overlay */

> int overlay(WINDOW *srcwin, WINDOW *dstwin);
> int overwrite(WINDOW *srcwin, WINDOW *dstwin);
> int copywin(WINDOW *srcwin, WINDOW *dstwin, int sminrow, int smincol, \
		int dminrow, int dmincol, int dmaxrow, int dmaxcol, \
		int overlay);

/* curs_pad */

> WINDOW *newpad(int lines_, int cols);
> WINDOW *subpad(WINDOW *orig, int lines_, int cols, int beginy, int beginx);
> int prefresh(WINDOW *pad, int pminrow, int pmincol, int sminrow, \
		int smincol, int smaxrow, int smaxcol);
> int pnoutrefresh(WINDOW *pad, int pminrow, int pmincol, int sminrow, \
		int smincol, int smaxrow, int smaxcol);
> int pechochar(WINDOW *pad, chtype ch);

/* curs_printw */

/* done in perl */

/* curs_refresh */

> int {w}refresh(void);
> int |w|noutrefresh(void);
> int doupdate(void);
> int <w>redrawwin(void);
> int |w|redrawln(int beg_line, int num_lines);

/* curs_scanw */

/* done in perl */

/* curs_scr_dump */

> int scr_dump(const char *filename);
> int scr_restore(const char *filename);
> int scr_init(const char *filename);
> int scr_set(const char *filename);

/* curs_scroll */

> int <w>scroll(void);
> int {w}scrl(int n);

/* curs_slk */

> int slk_init(int fmt);
> int slk_set(int labnum, char *label, int fmt);
> int slk_refresh(void);
> int slk_noutrefresh(void);
> char *slk_label(int labnum);
> int slk_clear(void);
> int slk_restore(void);
> int slk_touch(void);
> int slk_attron(chtype attrs);
> int slk_attrset(chtype attrs);
> attr_t slk_attr(void);
> int slk_attroff(chtype attrs);
> int slk_color(short color_pair_number);

/* curs_termattrs */

> int baudrate(void);
> char erasechar(void);
> int has_ic(void);
> int has_il(void);
> char killchar(void);
#ifdef C_LONG0ARGS
> {notest} char *longname(void);
#else
> {dup} char *longname(char *a, char *b);
#endif

> chtype termattrs(void);
> char *termname(void);

/* curs_touch */

> int <w>touchwin(void);
#ifdef C_TOUCH3ARGS
> {notest} int <w>touchline(int start, int count);
#else
> {dup} int <w>touchline(int y, int sx, int ex);
#endif

> int <w>untouchwin(void);
> int |w|touchln(int y, int n, int changed);
> int <w>is_linetouched(int line);
> int <w>is_wintouched(void);

/* curs_util */

> char *unctrl(chtype ch);
> {cast} char *keyname(int k);
#ifdef C_INTFILTER
> {itest} int filter(void);
#else
> {dup} void filter(void);
#endif
> void use_env(bool bf);
> int putwin(WINDOW *win, FILE *filep);
> WINDOW *getwin(FILE *filep);
> int delay_output(int ms);
> int flushinp(void);

/* curs_window */

> WINDOW *newwin(int nlines, int ncols, int beginy, int beginx);
> int <w>delwin(void);
> int <w>mvwin(int y, int x);
> WINDOW *<w>subwin(int nlines, int ncols, int beginy, int beginx);
> WINDOW *<w>derwin(int nlines, int ncols, int beginy, int beginx);
> int <w>mvderwin(int par_y, int par_x);
> WINDOW *<w>dupwin(void);
> void |w|syncup(void);
> int <w>syncok(bool bf);
> void |w|cursyncup(void);
> void |w|syncdown(void);

/* ncurses extension functions */

> int getmouse({out} MEVENT *event);
> int ungetmouse(MEVENT *event);
> mmask_t mousemask(mmask_t newmask, {out}{amp} mmask_t oldmask);
> bool |w|enclose(int y, int x);
> bool |w|mouse_trafo({out}{amp} int pY, {out}{amp} int pX, bool to_screen);
> int mouseinterval(int erval);
> int BUTTON_RELEASE(mmask_t e, int x);
> int BUTTON_PRESS(mmask_t e, int x);
> int BUTTON_CLICK(mmask_t e, int x);
> int BUTTON_DOUBLE_CLICK(mmask_t e, int x);
> int BUTTON_TRIPLE_CLICK(mmask_t e, int x);
> int BUTTON_RESERVED_EVENT(mmask_t e, int x);

> int use_default_colors(void);
> int assume_default_colors(int fg, int bg);
> int define_key(char *definition, int keycode);
> char *keybound(int keycode, int count);
> int keyok(int keycode, bool enable);
> int resizeterm(int lines, int cols);
> int {w}resize(int lines_, int columns);

/* DEC curses, I think */

> int <w>getmaxy(void);
> int <w>getmaxx(void);

/* old BSD curses calls */

> void <w>flusok(bool bf);
> {cast} char *getcap(char *term);
> int touchoverlap(WINDOW *src, WINDOW *dst);

/* Panel support */

> PANEL *new_panel(WINDOW *win);
> int bottom_panel(PANEL *pan);
> int top_panel(PANEL *pan);
> int show_panel(PANEL *pan);
> void update_panels(void);
> int hide_panel(PANEL *pan);
> WINDOW *panel_window(const PANEL *pan);
> int replace_panel(PANEL *pan, WINDOW *window);
> int move_panel(PANEL *pan, int starty, int startx);
> int panel_hidden(const PANEL *pan);
> PANEL *panel_above(const {opt} PANEL *pan);
> PANEL *panel_below(const {opt} PANEL *pan);
> int set_panel_userptr(PANEL *pan, const {cast} char *ptr);
> const {cast} char *panel_userptr(const PANEL *pan);
> int del_panel(PANEL *pan);

/* Menu support */

/* menu_attributes */

> int set_menu_fore(MENU *menu, chtype attr);
> chtype menu_fore(MENU *menu);
> int set_menu_back(MENU *menu, chtype attr);
> chtype menu_back(MENU *menu);
> int set_menu_grey(MENU *menu, chtype attr);
> chtype menu_grey(MENU *menu);
> int set_menu_pad(MENU *menu, int pad);
> int menu_pad(MENU *menu);

/* menu_cursor */

> int pos_menu_cursor(MENU *menu);

/* menu_driver */

> int menu_driver(MENU *menu, int c);

/* menu_format */

> int set_menu_format(MENU *menu, int rows, int cols);
> void menu_format(MENU *menu, {out}{amp} int rows, {out}{amp} int cols);

/* menu_items */

> int set_menu_items(MENU *menu, ITEM **items);
> ITEM **menu_items(MENU *menu);
> int item_count(MENU *menu);

/* menu_mark */

> int set_menu_mark(MENU *menu, char *mark);
> const {cast} char *menu_mark( const MENU *menu);

/* menu_new */

> MENU *new_menu(ITEM **items);
> int free_menu(MENU *menu);

/* menu_opts */

> int menu_opts(MENU *menu);
> int set_menu_opts(MENU *menu, int opts);
> int menu_opts_on(MENU *menu, int opts);
> int menu_opts_off(MENU *menu, int opts);

/* menu_pattern */

> int set_menu_pattern(MENU *menu, const char *pattern);
> char *menu_pattern(const MENU *menu);

/* menu_post */

> int post_menu(MENU *menu);
> int unpost_menu(MENU *menu);

/* menu_userptr */

> int set_menu_userptr(MENU *item, char *userptr);
> char *menu_userptr(MENU *item);

/* menu_win */

> int set_menu_win(MENU *menu, WINDOW *win);
> WINDOW *menu_win(MENU *menu);
> int set_menu_sub(MENU *menu, WINDOW *win);
> WINDOW *menu_sub(MENU *menu);
> int scale_menu(MENU *menu, {out}{amp} int rows, {out}{amp} int cols);

/* menu_item_current */

> int set_current_item(MENU *menu, const ITEM *item);
> ITEM *current_item(const MENU *menu);
> int set_top_row(MENU *menu, int row);
> int top_row(const MENU *menu);
> int item_index(const ITEM *item);

/* menu_item_name */

> const {cast} char *item_name( const ITEM *item);
> const {cast} char *item_description( const ITEM *item);

/* menu_item_new */

> ITEM *new_item(const char *name, const char *descr);
> int free_item(ITEM *item);

/* menu_item_opts */

> int set_item_opts(ITEM *item, int opts);
> int item_opts_on(ITEM *item, int opts);
> int item_opts_off(ITEM *item, int opts);
> int item_opts(ITEM *item);

/* menu_item_userptr */

> const {cast} char *item_userptr(const ITEM *item);
> int set_item_userptr(ITEM *item, const {cast} char *ptr);

/* menu_item_value */

> int set_item_value(ITEM *item, bool val);
> bool item_value(ITEM *item);

/* menu_item_visible */

> bool item_visible(ITEM *item);

/* ncurses menu extension functions */

> const {cast} char *menu_request_name(int request);
> int menu_request_by_name(const char *name);
> int set_menu_spacing(MENU *menu, int descr, int rows, int cols);
> int menu_spacing(const MENU *menu, {out}{amp} int descr, \
		   {out}{amp} int rows, {out}{amp} int cols);

/* Form support */

/* form_cursor */

> int pos_form_cursor(FORM *form);

/* form_data */

> bool data_ahead(const FORM *form);
> bool data_behind(const FORM *form);

/* form_driver */

> int form_driver(FORM *form, int c);

/* form_field */

> int set_form_fields(FORM *form, FIELD **fields);
> FIELD **form_fields(const FORM *form);
> int field_count(const FORM *form);
> int move_field(FIELD *field, int frow, int fcol);

/* form_new */

> FORM *new_form(FIELD **fields);
> int free_form(FORM *form);

/* form_new_page */

> int set_new_page(FIELD *field, bool new_page_flag);
> bool new_page(const FIELD *field);

/* form_opts */

> int set_form_opts(FORM *form, int opts);
> int form_opts_on(FORM *form, int opts);
> int form_opts_off(FORM *form, int opts);
> int form_opts(const FORM *form);

/* form_page */

> int set_current_field(FORM *form, FIELD *field);
> FIELD *current_field(const FORM *form);
> int set_form_page(FORM *form, int n);
> int form_page(const FORM *form);
> int field_index(const FIELD *field);

/* form_post */

> int post_form(FORM *form);
> int unpost_form(FORM *form);

/* form_userptr */

> int set_form_userptr(FORM *form, char *userptr);
> char *form_userptr(const FORM *form);

/* form_win */

> int set_form_win(FORM *form, WINDOW *win);
> WINDOW *form_win(const FORM *form);
> int set_form_sub(FORM *form, WINDOW *sub);
> WINDOW *form_sub(const FORM *form);
> int scale_form(const FORM *form, {out}{amp} int rows, {out}{amp} int cols);

/* form_field_attributes */

> int set_field_fore(FIELD *field, chtype attr);
> chtype field_fore(const FIELD *field);
> int set_field_back(FIELD *field, chtype attr);
> chtype field_back(const FIELD *field);
> int set_field_pad(FIELD *field, int pad);
> chtype field_pad(const FIELD *field);

/* form_field_buffer */

> int set_field_buffer(FIELD *field, int buf, const char *value);
> char *field_buffer(const FIELD *field, int buffer);
> int set_field_status(FIELD *field, bool status);
> bool field_status(const FIELD *field);
> int set_max_field(FIELD *field, int max);

/* form_field_info */

> int field_info(const FIELD *field, {out}{amp} int rows, \
                 {out}{amp} int cols, {out}{amp} int frow, \
                 {out}{amp} int fcol, {out}{amp} int nrow, \
                 {out}{amp} int nbuf);
> int dynamic_field_info(const FIELD *field, {out}{amp} int rows, \
	                 {out}{amp} int cols, {out}{amp} int max);

/* form_field_just */

> int set_field_just(FIELD *field, int justif);
> int field_just(const FIELD *field);

/* form_field_new */

> FIELD *new_field(int height, int width, int toprow, int leftcol, \
                 int offscreen, int nbuffers);
> FIELD *dup_field(FIELD *field, int toprow, int leftcol);
> FIELD *link_field(FIELD *field, int toprow, int leftcol);
> int free_field(FIELD *field);

/* form_field_opts */

> int set_field_opts(FIELD *field, int opts);
> int field_opts_on(FIELD *field, int opts);
> int field_opts_off(FIELD *field, int opts);
> int field_opts(const FIELD *field);

/* form_field_userptr */

> int set_field_userptr(FIELD *field, char *userptr);
> char *field_userptr(const FIELD *field);

/* form_field_validation */

> char *field_arg(const FIELD *field);

/* ncurses form extension functions */

> const {cast} char *form_request_name(int request);
> int form_request_by_name(const char *name);
