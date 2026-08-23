//
//  Availability.m
//  NeoFreeBird
//
//  Linux Theos toolchains do not always ship the iOS compiler-rt archive that
// provides __isOSVersionAtLeast. FFmpeg's VideoToolbox backend uses an
// availability check, so provide the small runtime entry point when the
// linker cannot obtain compiler-rt's copy.
//

#import <Foundation/Foundation.h>

__attribute__((visibility("hidden")))
int __isOSVersionAtLeast(int major, int minor, int patch) {
    NSOperatingSystemVersion current =
        [NSProcessInfo.processInfo operatingSystemVersion];

    if (current.majorVersion != major) {
        return current.majorVersion > major;
    }
    if (current.minorVersion != minor) {
        return current.minorVersion > minor;
    }
    return current.patchVersion >= patch;
}
