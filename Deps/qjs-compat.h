/* Force-included (-include) when QuickJS is built against the 10.9 SDK.
 *
 * quickjs-libc.c reads its clocks with clock_gettime(), which macOS only has
 * from 10.12. Before that the monotonic clock is mach_absolute_time() and
 * the wall clock gettimeofday(); this gives quickjs-libc the one function it
 * uses, built on those. */
#ifndef QJS_COMPAT_H
#define QJS_COMPAT_H

#include <time.h>
#include <sys/time.h>
#include <mach/mach_time.h>

#ifndef CLOCK_REALTIME
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 6

static inline int qjs_compat_clock_gettime(int clock, struct timespec *ts)
{
    if (clock == CLOCK_MONOTONIC) {
        static mach_timebase_info_data_t tb;
        if (tb.denom == 0) mach_timebase_info(&tb);
        uint64_t ns = mach_absolute_time() * tb.numer / tb.denom;
        ts->tv_sec = (time_t)(ns / 1000000000u);
        ts->tv_nsec = (long)(ns % 1000000000u);
        return 0;
    }
    struct timeval tv;
    gettimeofday(&tv, NULL);
    ts->tv_sec = tv.tv_sec;
    ts->tv_nsec = (long)tv.tv_usec * 1000;
    return 0;
}
#define clock_gettime qjs_compat_clock_gettime
#endif

#endif
