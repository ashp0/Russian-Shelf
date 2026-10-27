#import "RSClip.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

const double RSClipLeadIn = 0.15;
const double RSClipTail = 0.35;

static void RSCutClipOn(dispatch_queue_t queue, NSString *moviePath, double start, double end, NSString *outPath,
                        void (^done)(BOOL ok, NSString *problem))
{
    void (^finish)(BOOL, NSString *) = [[done copy] autorelease];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:moviePath] options:nil];
    double duration = CMTimeGetSeconds([asset duration]);
    if (![[NSFileManager defaultManager] fileExistsAtPath:moviePath] || !isfinite(duration) || duration <= 0 ||
        [[asset tracksWithMediaType:AVMediaTypeAudio] count] == 0) {
        dispatch_async(queue, ^{ finish(NO, @"The video has no sound to cut the line from."); });
        return;
    }
    double from = MAX(0, start - RSClipLeadIn), to = MIN(duration, MAX(end, start) + RSClipTail);
    if (to - from < 0.2) {
        dispatch_async(queue, ^{ finish(NO, @"The line is too short to cut."); });
        return;
    }
    AVAssetExportSession *session = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    if (session == nil) {
        dispatch_async(queue, ^{ finish(NO, @"This Mac can’t write the line’s sound."); });
        return;
    }
    NSString *temp = [[outPath stringByDeletingPathExtension] stringByAppendingString:@".partial.m4a"];
    [[NSFileManager defaultManager] removeItemAtPath:temp error:NULL];
    [session setOutputURL:[NSURL fileURLWithPath:temp]];
    [session setOutputFileType:AVFileTypeAppleM4A];
    [session setTimeRange:CMTimeRangeFromTimeToTime(CMTimeMakeWithSeconds(from, 600), CMTimeMakeWithSeconds(to, 600))];
    [session retain];
    [session exportAsynchronouslyWithCompletionHandler:^{
        BOOL ok = [session status] == AVAssetExportSessionStatusCompleted;
        NSString *problem = nil;
        NSFileManager *fm = [NSFileManager defaultManager];
        if (ok) {
            [fm removeItemAtPath:outPath error:NULL];
            ok = [fm moveItemAtPath:temp toPath:outPath error:NULL];
            if (!ok) problem = @"The line’s sound couldn’t be saved.";
        } else {
            [fm removeItemAtPath:temp error:NULL];
            problem = [NSString stringWithFormat:@"The line’s sound couldn’t be cut (%@).",
                       [[session error] localizedDescription] ?: @"no reason given"];
        }
        [problem retain];
        [session release];
        dispatch_async(queue, ^{
            finish(ok, problem);
            [problem release];
        });
    }];
}

void RSCutClip(NSString *moviePath, double start, double end, NSString *outPath, void (^done)(BOOL ok, NSString *problem))
{
    RSCutClipOn(dispatch_get_main_queue(), moviePath, start, end, outPath, done);
}

BOOL RSCutClipNow(NSString *moviePath, double start, double end, NSString *outPath, NSString **problem)
{
    dispatch_queue_t queue = dispatch_queue_create("com.russianshelf.clip", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    __block BOOL result = NO;
    __block NSString *why = nil;
    RSCutClipOn(queue, moviePath, start, end, outPath, ^(BOOL ok, NSString *p) {
        result = ok;
        why = [p copy];
        dispatch_semaphore_signal(finished);
    });
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
    dispatch_release(finished);
    dispatch_release(queue);
    if (problem) *problem = [why autorelease];
    else [why release];
    return result;
}

double RSMediaDuration(NSString *path)
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return 0;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    double d = CMTimeGetSeconds([asset duration]);
    return isfinite(d) && d > 0 ? d : 0;
}
