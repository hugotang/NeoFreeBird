# Every setting comes in from the environment: build.py reads tweak.json and
# passes the settings, the package scheme and where to build in.

ifeq ($(TWEAK_NAME),)
$(error No TWEAK_NAME in the environment; build with ./build.py)
endif

include $(THEOS)/makefiles/common.mk

$(TWEAK_NAME)_FILES = $(TWEAK_FILES)
$(TWEAK_NAME)_FRAMEWORKS = $(TWEAK_FRAMEWORKS)
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = $(TWEAK_PRIVATE_FRAMEWORKS)
$(TWEAK_NAME)_EXTRA_FRAMEWORKS = $(TWEAK_EXTRA_FRAMEWORKS)
$(TWEAK_NAME)_OBJ_FILES = $(TWEAK_OBJ_FILES)
$(TWEAK_NAME)_CFLAGS = $(TWEAK_CFLAGS)

# The settings pages subclass a Twitter class, and Twitter's frameworks can't be
# linked against. Leaving the superclass undefined lets dyld bind it at load,
# where TwitterSPMMigration is already in the process.
$(TWEAK_NAME)_LDFLAGS = -Wl,-U,_OBJC_CLASS_\$$_TFNItemsDataViewController \
                        -Wl,-U,_OBJC_METACLASS_\$$_TFNItemsDataViewController

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += $(TWEAK_SUBPROJECTS)
include $(THEOS_MAKE_PATH)/aggregate.mk
