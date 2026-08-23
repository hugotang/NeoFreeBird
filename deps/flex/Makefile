TARGET := iphone:clang:16.5:14.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

FLEX_ROOT := upstream

SOURCES := $(shell find $(FLEX_ROOT)/Classes \( -name '*.c' -o -name '*.m' -o -name '*.mm' \))
# FLEX is linked as its own dylib, so it needs the availability runtime
# fallback independently of the main tweak target.
SOURCES += ../../src/Core/Availability.m
IMPORTS := $(addprefix -I,$(shell find $(FLEX_ROOT)/Classes -type d))

TWEAK_NAME := libbhFLEX

$(TWEAK_NAME)_FILES := $(SOURCES)
$(TWEAK_NAME)_FRAMEWORKS := CoreGraphics UIKit ImageIO QuartzCore
$(TWEAK_NAME)_LIBRARIES := sqlite3 z
$(TWEAK_NAME)_CFLAGS := -fobjc-arc -w $(IMPORTS)
$(TWEAK_NAME)_CCFLAGS := -std=gnu++11

include $(THEOS_MAKE_PATH)/tweak.mk
