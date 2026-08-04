#import "BHTTwitter1214Compatibility.h"

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        BHTInstallTwitter1214Compatibility();
    });
}
