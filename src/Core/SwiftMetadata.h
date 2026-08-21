//
//  SwiftMetadata.h
//  NeoFreeBird
//

#import <Foundation/Foundation.h>

// An enum's getEnumTag value witness. Tags number payload cases before empty
// ones, each group in declaration order — match them via SwiftEnumTagForCase.
typedef unsigned (*SwiftEnumTagGetter)(const void* value, const void* metadata);

const void* SwiftTypeMetadataForMangledName(const char* mangledName);

int32_t SwiftFieldOffsetForName(const void* metadata, const char* name);

int SwiftEnumTagForCase(const void* metadata, const char* name);

SwiftEnumTagGetter SwiftEnumTagGetterForMetadata(const void* metadata);
