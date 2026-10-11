#include "RSDate.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Howard Hinnant's civil-date algorithms: exact for every Gregorian date,
// no tables, no library calls.
long RSDaysFromCivil(int y, int m, int d)
{
    y -= m <= 2;
    long era = (y >= 0 ? y : y - 399) / 400;
    unsigned yoe = (unsigned)(y - era * 400);
    unsigned doy = (153u * (unsigned)(m + (m > 2 ? -3 : 9)) + 2u) / 5u + (unsigned)d - 1u;
    unsigned doe = yoe * 365u + yoe / 4u - yoe / 100u + doy;
    return era * 146097L + (long)doe - 719468L;
}

void RSCivilFromDays(long z, int *y, int *m, int *d)
{
    z += 719468L;
    long era = (z >= 0 ? z : z - 146096L) / 146097L;
    unsigned doe = (unsigned)(z - era * 146097L);
    unsigned yoe = (doe - doe / 1460u + doe / 36524u - doe / 146096u) / 365u;
    long yy = (long)yoe + era * 400L;
    unsigned doy = doe - (365u * yoe + yoe / 4u - yoe / 100u);
    unsigned mp = (5u * doy + 2u) / 153u;
    unsigned dd = doy - (153u * mp + 2u) / 5u + 1u;
    unsigned mm = mp < 10u ? mp + 3u : mp - 9u;
    *y = (int)(yy + (mm <= 2u));
    *m = (int)mm;
    *d = (int)dd;
}

int RSWeekday(long z)
{
    return (int)(z >= -4 ? (z + 4) % 7 : (z + 5) % 7 + 6);
}

int RSDaysInMonth(int y, int m)
{
    static const int days[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (m < 1 || m > 12) return 0;
    if (m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) return 29;
    return days[m - 1];
}

long RSParseDay(const char *text, int *ok)
{
    int y, m, d, used = 0;
    *ok = 0;
    if (text == NULL || strlen(text) != 10 || text[4] != '-' || text[7] != '-') return 0;
    if (sscanf(text, "%4d-%2d-%2d%n", &y, &m, &d, &used) != 3 || used != 10) return 0;
    if (y < 2000 || y > 2999 || m < 1 || m > 12 || d < 1 || d > RSDaysInMonth(y, m)) return 0;
    *ok = 1;
    return RSDaysFromCivil(y, m, d);
}

time_t RSNowTime(void)
{
    const char *fixed = getenv("RUSSIAN_SHELF_NOW");
    if (fixed != NULL) {
        struct tm tm;
        memset(&tm, 0, sizeof tm);
        int y, mo, d, h = 0, mi = 0;
        if (sscanf(fixed, "%d-%d-%d %d:%d", &y, &mo, &d, &h, &mi) >= 3) {
            tm.tm_year = y - 1900; tm.tm_mon = mo - 1; tm.tm_mday = d;
            tm.tm_hour = h; tm.tm_min = mi; tm.tm_isdst = -1;
            time_t t = mktime(&tm);
            if (t != (time_t)-1) return t;
        }
    }
    return time(NULL);
}

long RSToday(void)
{
    time_t t = RSNowTime();
    struct tm tm;
    if (localtime_r(&t, &tm) == NULL) return 0;
    return RSDaysFromCivil(tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday);
}
