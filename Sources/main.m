#import <Cocoa/Cocoa.h>
#import "RSController.h"
#import "RSSelfTest.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        // "Shelf.app/Contents/MacOS/Shelf --selftest": checks
        // this Mac can do everything the app needs, and says what it found.
        for (int i = 1; i < argc; i++)
            if (strcmp(argv[i], "--selftest") == 0) return RSSelfTestRun();
        NSApplication *app = [NSApplication sharedApplication];
        RSController *controller = [[RSController alloc] initWithLibrary:nil studyFolder:nil];
        [app setDelegate:controller];
        [app run];
        [controller release];
    }
    return 0;
}
