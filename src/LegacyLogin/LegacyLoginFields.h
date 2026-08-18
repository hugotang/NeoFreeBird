//
//  LegacyLoginFields.h
//  NeoFreeBird
//

#import <Foundation/Foundation.h>

#import "Headers/Login.h"

@interface LegacyLoginFields : NSObject

// nil when the app's form classes are missing.
+ (instancetype)fields;

@property (nonatomic, readonly) TFNLegacyForm* form;
@property (nonatomic, readonly) TFNLegacyFormField* identifierField;
@property (nonatomic, readonly) TFNLegacyFormField* passwordField;

@property (nonatomic, copy) NSString* identifier;

- (BOOL)isSubmittable;

@end
