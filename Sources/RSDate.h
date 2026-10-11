// Dates without NSCalendar, as in Syllabus (SYDate.c).
//
// A shelf starts on a calendar day in the Mac's own time zone, so days are
// kept as civil dates, counted from 1970-01-01, and compared as integers. No
// calendar or time zone objects: a current SDK binds those to CoreFoundation,
// and the app is linked against what 10.9 really exports (`make verify`).

#ifndef RS_DATE_H
#define RS_DATE_H

#include <time.h>

long RSDaysFromCivil(int y, int m, int d);
void RSCivilFromDays(long days, int *y, int *m, int *d);
int  RSWeekday(long days);                   // 0 = Sunday ... 6 = Saturday
int  RSDaysInMonth(int y, int m);

// "2026-10-12" -> a day number; 0 and *ok = 0 for anything else.
long RSParseDay(const char *text, int *ok);

// Today, from the Mac's clock and time zone. RUSSIAN_SHELF_NOW="YYYY-MM-DD
// HH:MM" in the environment overrides it, for tests and screenshots.
long RSToday(void);
time_t RSNowTime(void);

#endif
