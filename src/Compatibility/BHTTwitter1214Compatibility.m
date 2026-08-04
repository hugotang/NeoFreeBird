#import "BHTTwitter1214Compatibility.h"

#import "BHTImmersiveTimestampCompatibility.h"
#import "BHTTabBarCompatibility.h"

void BHTInstallTwitter1214Compatibility(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BHTInstallTabBarCompatibility();
        BHTInstallImmersiveTimestampCompatibility();
    });
}
