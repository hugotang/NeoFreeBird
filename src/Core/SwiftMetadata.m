//
//  SwiftMetadata.m
//  NeoFreeBird
//

#import "Core/SwiftMetadata.h"

#import <dlfcn.h>

const void* SwiftTypeMetadataForMangledName(const char* mangledName) {
    static const void* (*getType)(const char*, size_t, const void*,
                                  const void* const*);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        getType = dlsym(RTLD_DEFAULT, "swift_getTypeByMangledNameInEnvironment");
    });
    return getType ? getType(mangledName, strlen(mangledName), NULL, NULL)
                   : NULL;
}

// Swift 4-byte relative pointer; 0 means absent.
static const void* relativePointer(const void* base) {
    int32_t offset = *(const int32_t*)base;
    return offset ? (const uint8_t*)base + offset : NULL;
}

// The reflection field descriptor: records at +16, each holding relative
// pointers to the case/field type (+4) and name (+8), in declaration order.
static const uint8_t* fieldDescriptorForMetadata(const void* metadata) {
    const uint8_t* descriptor =
        *(const uint8_t* const*)((const uint8_t*)metadata + 8);
    return relativePointer(descriptor + 16);
}

int32_t SwiftFieldOffsetForName(const void* metadata, const char* name) {
    const uint8_t* fields = fieldDescriptorForMetadata(metadata);
    if (!fields) {
        return -1;
    }

    const uint8_t* descriptor =
        *(const uint8_t* const*)((const uint8_t*)metadata + 8);
    uint32_t offsetVectorOffset = *(const uint32_t*)(descriptor + 24);
    if (offsetVectorOffset == 0) {
        return -1;
    }
    const int32_t* offsets = (const int32_t*)((const uint8_t*)metadata +
                                              offsetVectorOffset * sizeof(void*));

    uint16_t recordSize = *(const uint16_t*)(fields + 10);
    uint32_t numRecords = *(const uint32_t*)(fields + 12);
    const uint8_t* record = fields + 16;
    for (uint32_t index = 0; index < numRecords; index++, record += recordSize) {
        const char* fieldName = relativePointer(record + 8);
        if (fieldName && strcmp(fieldName, name) == 0) {
            return offsets[index];
        }
    }
    return -1;
}

// Payload cases are the records with a type reference.
int SwiftEnumTagForCase(const void* metadata, const char* name) {
    const uint8_t* fields = fieldDescriptorForMetadata(metadata);
    if (!fields) {
        return -1;
    }

    uint16_t recordSize = *(const uint16_t*)(fields + 10);
    uint32_t numRecords = *(const uint32_t*)(fields + 12);

    unsigned payloadCount = 0;
    const uint8_t* record = fields + 16;
    for (uint32_t index = 0; index < numRecords; index++, record += recordSize) {
        if (relativePointer(record + 4)) {
            payloadCount++;
        }
    }

    unsigned payloadSeen = 0, emptySeen = 0;
    record = fields + 16;
    for (uint32_t index = 0; index < numRecords; index++, record += recordSize) {
        BOOL payload = relativePointer(record + 4) != NULL;
        unsigned tag = payload ? payloadSeen++ : payloadCount + emptySeen++;
        const char* caseName = relativePointer(record + 8);
        if (caseName && strcmp(caseName, name) == 0) {
            return (int)tag;
        }
    }
    return -1;
}

// getEnumTag lives after the 8 base witnesses and size/stride/flags/extra
// inhabitants in an enum's value witness table (frozen Swift ABI).
SwiftEnumTagGetter SwiftEnumTagGetterForMetadata(const void* metadata) {
    const uint8_t* witnesses =
        *(const uint8_t* const*)((const uint8_t*)metadata - 8);
    return witnesses ? *(const SwiftEnumTagGetter*)(witnesses + 88) : NULL;
}
