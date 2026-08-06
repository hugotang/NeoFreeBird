#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString* BHTEffectiveSharingHost(NSString* _Nullable selectedHost);
FOUNDATION_EXPORT NSString* _Nullable BHTNormalizedTwitterHandle(
    NSString* _Nullable handle);
FOUNDATION_EXPORT NSString* _Nullable BHTCleanShareURLString(
    NSString* _Nullable urlString,
    NSString* _Nullable selectedHost,
    BOOL removeFragment);
FOUNDATION_EXPORT NSString* _Nullable BHTCanonicalTweetURLString(
    NSString* _Nullable handle,
    long long statusID,
    NSString* _Nullable selectedHost);
FOUNDATION_EXPORT NSString* _Nullable BHTTweetHandleFromURLString(
    NSString* _Nullable urlString);
FOUNDATION_EXPORT long long BHTTweetStatusIDFromURLString(
    NSString* _Nullable urlString);

NS_ASSUME_NONNULL_END
