//
//  RuntimeSubclass.h
//  NeoFreeBird
//
//  Subclasses of the app's own classes, built at load time: naming an app class
//  at compile time emits a reference nothing defines and the link fails, so the
//  subclass is allocated from the runtime instead.
//
//    SUBCLASS(LegacyLoginForm, TFNLegacyForm)
//
//    SUBCLASS_METHOD(LegacyLoginForm, sections, sections, "@@:", NSArray*) {
//        return ...;
//    }
//
//  `name` is a plain identifier unique within the file, since a selector's
//  colons cannot appear in one. The subclass Class is Nil when the superclass is
//  missing, so call sites must fall back to the app's own behaviour. Classes load
//  at a lower priority than their methods.
//

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

// One of the app's exported NSString* constants, or nil when this version has none.
static inline NSString* NFBAppConstant(const char* symbol) {
    NSString* __unsafe_unretained const* address =
        (NSString* __unsafe_unretained const*)dlsym(RTLD_DEFAULT, symbol);
    return address ? *address : nil;
}

#define SUBCLASS(name, superName)                                      \
    static Class name;                                                 \
    __attribute__((constructor(101))) static void loadsub_##name(void) { \
        Class super = objc_getClass(#superName);                       \
        name = super ? objc_allocateClassPair(super, #name, 0) : Nil;  \
        if (name) {                                                    \
            objc_registerClassPair(name);                             \
        }                                                              \
    }

// `types` is an Objective-C type encoding, so "v@:" for a -(void) taking nothing.
#define SUBCLASS_METHOD(cls, name, sel, types, ret, ...)                                        \
    static ret sub_##cls##_##name(id, SEL, ##__VA_ARGS__);                                      \
    __attribute__((constructor(102))) static void loadsubm_##cls##_##name(void) {               \
        if (cls != Nil) {                                                                       \
            class_addMethod(cls, @selector(sel), (IMP)sub_##cls##_##name, types);               \
        }                                                                                       \
    }                                                                                           \
    static ret sub_##cls##_##name(id self, SEL _cmd, ##__VA_ARGS__)

// The superclass's implementation of the method being run:
//
//   SUPER(void)(SUPER_TARGET(LegacyLoginScreenController), _cmd);
//   BOOL handled = SUPER(BOOL, id)(SUPER_TARGET(LegacyLoginScreenController), _cmd, field);
#define SUPER(ret, ...) ((ret (*)(struct objc_super*, SEL, ##__VA_ARGS__))objc_msgSendSuper)
#define SUPER_TARGET(cls) (&(struct objc_super){self, class_getSuperclass(cls)})
