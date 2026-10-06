// Compiled by native-space-smoke.sh. Moves only a disposable window owned by a child process.
#import <AppKit/AppKit.h>
#import "Momentum-Bridging-Header.h"

static NSArray *Membership(CGWindowID window) {
    return CFBridgingRelease(CGSCopySpacesForWindows(CGSMainConnectionID(), 7, (__bridge CFArrayRef)@[@(window)]));
}

static NSArray *VisibleSpaces(void) {
    NSArray *displays = CFBridgingRelease(MomentumCopyManagedDisplaySpaces(CGSMainConnectionID()));
    NSMutableArray *current = [NSMutableArray array];
    for (NSDictionary *display in displays) {
        if (display[@"Current Space"][@"id64"]) [current addObject:display[@"Current Space"][@"id64"]];
    }
    return current;
}

static CGPoint Cursor(void) {
    CGEventRef event = CGEventCreate(NULL);
    CGPoint point = CGEventGetLocation(event);
    CFRelease(event);
    return point;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (argc == 2 && strcmp(argv[1], "--fixture") == 0) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
            NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 420, 200)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            window.title = @"Momentum native Space test (temporary)";
            [window orderFrontRegardless];
            // Report readiness only after WindowServer has registered Space membership.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                printf("%d\n", (int)window.windowNumber); fflush(stdout);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ exit(2); });
            [NSApp run];
            return 0;
        }

        NSTask *fixture = [[NSTask alloc] init];
        fixture.executableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[0]]];
        fixture.arguments = @[@"--fixture"];
        NSPipe *pipe = [NSPipe pipe];
        fixture.standardOutput = pipe;
        NSError *error;
        if (![fixture launchAndReturnError:&error]) { NSLog(@"Could not launch fixture: %@", error); return 2; }
        int status = 1;
        @try {
            NSData *data = [pipe.fileHandleForReading availableData];
            CGWindowID window = (CGWindowID)[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] intValue];
            NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
            BOOL ownedByFixture = NO;
            for (NSDictionary *entry in windows) {
                if ([entry[(__bridge NSString *)kCGWindowNumber] unsignedIntValue] == window &&
                    [entry[(__bridge NSString *)kCGWindowOwnerPID] intValue] == fixture.processIdentifier) ownedByFixture = YES;
            }
            if (!window || !ownedByFixture) { fprintf(stderr, "FAIL: fixture window ownership not verified\n"); return 3; }
            NSArray *initial = Membership(window);
            NSNumber *source = initial.count == 1 ? initial.firstObject : nil;
            NSNumber *destination = nil;
            NSArray *displays = CFBridgingRelease(MomentumCopyManagedDisplaySpaces(CGSMainConnectionID()));
            for (NSDictionary *display in displays) {
                BOOL containsSource = NO;
                for (NSDictionary *space in display[@"Spaces"]) {
                    if ([space[@"id64"] isEqual:source]) containsSource = YES;
                }
                if (!containsSource) continue;
                for (NSDictionary *space in display[@"Spaces"]) {
                    if ([space[@"type"] intValue] == 0 && ![space[@"id64"] isEqual:source]) {
                        destination = space[@"id64"]; break;
                    }
                }
            }
            if (!source || !destination) { fprintf(stderr, "SKIP: need two existing Desktops on the fixture display\n"); return 4; }
            NSArray *visible = VisibleSpaces();
            CGPoint cursor = Cursor();
            BOOL succeeded = YES;
            int confirmedMoves = 0;
            for (int cycle = 0; cycle < 10; ++cycle) {
                for (NSNumber *target in @[destination, source]) {
                    BOOL submitted = MomentumRequestNativeSpaceMove(window, target.unsignedLongLongValue);
                    BOOL confirmed = NO;
                    for (int attempt = 0; submitted && attempt <= 100; ++attempt) {
                        NSArray *membership = Membership(window);
                        if (membership.count == 1 && [membership.firstObject isEqual:target]) { confirmed = YES; break; }
                        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
                    }
                    printf("cycle=%d window=%u target=%llu submitted=%s confirmed=%s\n", cycle + 1, window,
                           target.unsignedLongLongValue, submitted ? "yes" : "NO", confirmed ? "yes" : "NO");
                    if (confirmed) ++confirmedMoves;
                    else succeeded = NO;
                }
                if (!succeeded) break;
            }
            BOOL desktopUnchanged = [visible isEqual:VisibleSpaces()];
            BOOL cursorUnchanged = CGPointEqualToPoint(cursor, Cursor());
            printf("%s: %d/20 moves verified; visible Desktops unchanged=%s; cursor unchanged=%s\n",
                   succeeded && desktopUnchanged && cursorUnchanged ? "PASS" : "FAIL", confirmedMoves,
                   desktopUnchanged ? "yes" : "NO", cursorUnchanged ? "yes" : "NO");
            status = succeeded && desktopUnchanged && cursorUnchanged ? 0 : 5;
        } @finally {
            if (fixture.running) [fixture terminate];
            [fixture waitUntilExit];
        }
        return status;
    }
}
