/* Linked into Deps/python3's interpreter and every module (build-python.sh).
 *
 * CPython checks the running OS with __builtin_available, which clang turns
 * into calls to __isPlatformVersionAtLeast / __isOSVersionAtLeast. Today's
 * compiler-rt implements those with _availability_version_check, a libSystem
 * function only macOS 11 and later have, so nothing built against the 10.9
 * SDK links. These do the same job from the Darwin version in kern.osrelease:
 * Darwin 13 is OS X 10.9, Darwin 19 is 10.15, Darwin 20 and later are 11 and
 * later (reported low for the newest systems, which still passes every check
 * CPython makes: none asks for more than macOS 11). Hidden, so each module
 * keeps its own copy and nothing is exported. */

#include <stdint.h>
#include <stdlib.h>
#include <sys/sysctl.h>

static void PyAvailOSVersion(int32_t *major, int32_t *minor)
{
    char release[32];
    size_t size = sizeof release;
    int darwin = 13;
    if (sysctlbyname("kern.osrelease", release, &size, NULL, 0) == 0) darwin = atoi(release);
    if (darwin >= 20) { *major = darwin - 9; *minor = 0; }
    else { *major = 10; *minor = darwin - 4; }
}

__attribute__((visibility("hidden")))
int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t subminor)
{
    int32_t have_major, have_minor;
    PyAvailOSVersion(&have_major, &have_minor);
    if (have_major != major) return have_major > major;
    if (have_minor != minor) return have_minor > minor;
    return subminor <= 0;
}

__attribute__((visibility("hidden")))
int32_t __isPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor, uint32_t subminor)
{
    (void)platform;     /* always macOS here */
    return __isOSVersionAtLeast((int32_t)major, (int32_t)minor, (int32_t)subminor);
}
