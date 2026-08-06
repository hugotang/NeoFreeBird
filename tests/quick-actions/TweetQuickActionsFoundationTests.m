#import <Foundation/Foundation.h>
#import "Core/BHTShareURL.h"

static NSUInteger assertions = 0;
static NSUInteger failures = 0;

static void AssertEqual(id actual, id expected, NSString* label) {
    assertions++;
    if ((actual == nil && expected == nil) || [actual isEqual:expected]) {
        return;
    }
    failures++;
    NSLog(@"FAIL %@: expected %@, got %@", label, expected, actual);
}

static void TestURLs(void) {
    AssertEqual(BHTEffectiveSharingHost(nil), @"x.com", @"default host");
    AssertEqual(BHTEffectiveSharingHost(@" https://FxTwitter.com/path "),
                @"fxtwitter.com", @"normalized host");
    AssertEqual(BHTNormalizedTwitterHandle(@" @@alice "), @"alice",
                @"normalized handle");

    NSString* source =
        @"https://twitter.com/alice/status/123?s=20&t=token&lang=en#media";
    AssertEqual(BHTCleanShareURLString(source, @"fxtwitter.com", YES),
                @"https://fxtwitter.com/alice/status/123?lang=en",
                @"clean fallback URL");
    AssertEqual(BHTCleanShareURLString(source, nil, NO),
                @"https://twitter.com/alice/status/123?lang=en#media",
                @"preserve existing host and fragment");
    AssertEqual(BHTCanonicalTweetURLString(@"@alice", 123, nil),
                @"https://x.com/alice/status/123", @"canonical URL");
    AssertEqual(BHTCanonicalTweetURLString(nil, 123, nil), nil,
                @"canonical URL requires handle");
    AssertEqual(BHTTweetHandleFromURLString(source), @"alice",
                @"handle from URL");
    AssertEqual(@(BHTTweetStatusIDFromURLString(source)), @123,
                @"status ID from URL");
    AssertEqual(BHTTweetHandleFromURLString(@"not-a-tweet/status/123"), nil,
                @"reject invalid Tweet URL handle");
    AssertEqual(@(BHTTweetStatusIDFromURLString(@"not-a-tweet/status/123")), @0,
                @"reject invalid Tweet URL ID");
}

int main(void) {
    @autoreleasepool {
        TestURLs();
        if (failures > 0) {
            NSLog(@"Tweet Quick Actions Foundation tests failed: %lu/%lu",
                  (unsigned long)failures, (unsigned long)assertions);
            return 1;
        }
        NSLog(@"Tweet Quick Actions Foundation tests passed: %lu assertions",
              (unsigned long)assertions);
    }
    return 0;
}
