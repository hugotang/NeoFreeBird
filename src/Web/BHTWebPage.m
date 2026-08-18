//
//  BHTWebPage.m
//  NeoFreeBird
//

#import "BHTWebPage.h"

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

#import "Core/BHTBundle.h"

@interface WKWebView (AsyncJavaScript)
- (void)callAsyncJavaScript:(NSString*)functionBody
                  arguments:(NSDictionary<NSString*, id>*)arguments
                    inFrame:(WKFrameInfo*)frame
             inContentWorld:(WKContentWorld*)contentWorld
          completionHandler:(void (^)(id result, NSError* error))completionHandler;
@end

static NSString* const BHTWebPageTokenScript = @"TransactionID.js";

// Signed out, the root is a landing page that never loads the web app.
static NSString* const BHTWebPageURL = @"https://x.com/i/flow/login";

static NSString* gUserAgent;

static const NSTimeInterval BHTWebPageLoadTimeout = 20;
static const NSTimeInterval BHTWebPageAnswerTimeout = 10;
static const NSTimeInterval BHTWebPageIdleTimeout = 10 * 60;

@interface BHTWebPage () <WKNavigationDelegate>
@end

@implementation BHTWebPage {
    UIWindow* _window;
    WKWebView* _webView;
    BOOL _loaded;
    NSMutableArray<void (^)(void)>* _pending;
    NSDate* _lastUsed;
}

// Everything here is main-thread only, since a web view is.
+ (instancetype)shared {
    static BHTWebPage* shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [self new];
    });

    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pending = [NSMutableArray new];
    }

    return self;
}

- (NSString*)source {
    NSURL* url = [[BHTBundle sharedBundle] pathForFile:BHTWebPageTokenScript];
    return url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
}

- (UIWindowScene*)scene {
    UIWindowScene* fallback = nil;
    for (UIScene* candidate in UIApplication.sharedApplication.connectedScenes) {
        if (![candidate isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        if (candidate.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene*)candidate;
        }
        fallback = fallback ?: (UIWindowScene*)candidate;
    }

    return fallback;
}

// A web view with no window is throttled to the point of never finishing.
- (BOOL)build {
    if (_webView) {
        return YES;
    }

    NSString* source = self.source;
    UIWindowScene* scene = self.scene;
    if (source.length == 0 || !scene) {
        return NO;
    }

    WKWebViewConfiguration* configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    [configuration.userContentController
        addUserScript:[[WKUserScript alloc] initWithSource:source
                                             injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                          forMainFrameOnly:YES]];

    _webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 390, 844)
                                  configuration:configuration];
    _webView.navigationDelegate = self;
    _webView.userInteractionEnabled = NO;

    _window = [[UIWindow alloc] initWithWindowScene:scene];
    _window.frame = CGRectMake(-4000, -4000, 390, 844);
    _window.windowLevel = UIWindowLevelNormal - 1000;
    _window.userInteractionEnabled = NO;
    _window.rootViewController = [UIViewController new];
    [_window.rootViewController.view addSubview:_webView];
    _window.hidden = NO;

    [_webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:BHTWebPageURL]]];

    // Tied to this web view, so a stale deadline cannot cut short its replacement.
    __weak typeof(self) weakSelf = self;
    WKWebView* loading = _webView;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(BHTWebPageLoadTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       BHTWebPage* page = weakSelf;
                       if (page && page->_webView == loading && !page->_loaded) {
                           [page giveUp];
                       }
                   });

    return YES;
}

- (void)giveUp {
    [self finishPending];
    [self tearDown];
}

- (void)tearDown {
    _window.hidden = YES;
    _window.rootViewController = nil;
    _window = nil;
    _webView.navigationDelegate = nil;
    _webView = nil;
    _loaded = NO;
}

- (void)tearDownWhenIdle {
    _lastUsed = NSDate.date;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(BHTWebPageIdleTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       BHTWebPage* page = weakSelf;
                       if (page && page->_lastUsed.timeIntervalSinceNow <= -BHTWebPageIdleTimeout) {
                           [page tearDown];
                       }
                   });
}

- (void)finishPending {
    NSArray<void (^)(void)>* pending = [_pending copy];
    [_pending removeAllObjects];
    for (void (^resume)(void) in pending) {
        resume();
    }
}

#pragma mark - Navigation

// x.com sends an in-app reader to the app, and that hop interrupts the load rather
// than failing it.
- (void)webView:(WKWebView*)webView
    decidePolicyForNavigationAction:(WKNavigationAction*)action
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decide {
    NSString* scheme = action.request.URL.scheme.lowercaseString;
    BOOL web = [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"];
    decide(web ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
    _loaded = YES;

    __weak typeof(self) weakSelf = self;
    [webView evaluateJavaScript:@"navigator.userAgent"
              completionHandler:^(id agent, NSError* error) {
                  if ([agent isKindOfClass:NSString.class] && ((NSString*)agent).length) {
                      gUserAgent = agent;
                  }

                  [weakSelf finishPending];
              }];
}

- (void)webView:(WKWebView*)webView
    didFailProvisionalNavigation:(WKNavigation*)navigation
                       withError:(NSError*)error {
    if (_loaded) {
        return;
    }

    [self giveUp];
}

#pragma mark - Asking the page

- (void)askPage:(NSString*)body
      arguments:(NSDictionary<NSString*, id>*)arguments
     completion:(void (^)(id))completion {
    if (![self build]) {
        [self finishPending];
        completion(nil);
        return;
    }

    [self tearDownWhenIdle];

    if (!_loaded) {
        __weak typeof(self) weakSelf = self;
        [_pending addObject:^{
            [weakSelf run:body arguments:arguments completion:completion];
        }];
        return;
    }

    [self run:body arguments:arguments completion:completion];
}

- (void)run:(NSString*)body
     arguments:(NSDictionary<NSString*, id>*)arguments
    completion:(void (^)(id))completion {
    if (!_loaded || !_webView || body.length == 0) {
        completion(nil);
        return;
    }

    __block BOOL answered = NO;
    void (^answer)(id) = ^(id result) {
        if (!answered) {
            answered = YES;
            completion(result);
        }
    };

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(BHTWebPageAnswerTimeout * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            answer(nil);
        });

    // The page's own world, since what is asked of it only exists there.
    [_webView callAsyncJavaScript:body
                        arguments:arguments
                          inFrame:nil
                   inContentWorld:WKContentWorld.pageWorld
                completionHandler:^(id result, NSError* error) {
                    answer(error ? nil : result);
                }];
}

+ (void)askPage:(NSString*)body
      arguments:(NSDictionary<NSString*, id>*)arguments
     completion:(void (^)(id))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.shared askPage:body arguments:arguments ?: @{} completion:completion];
    });
}

#pragma mark - Tokens

+ (void)tokenForPath:(NSString*)path
              method:(NSString*)method
          completion:(void (^)(NSString*))completion {
    if (path.length == 0 || method.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
        return;
    }

    [self askPage:@"return await window.__twTransactionID(path, method);"
         arguments:@{@"path" : path, @"method" : method}
        completion:^(id answer) {
            NSString* token = [answer isKindOfClass:NSString.class] ? answer : nil;
            completion(token.length ? token : nil);
        }];
}

+ (NSString*)userAgent {
    return gUserAgent;
}

@end
