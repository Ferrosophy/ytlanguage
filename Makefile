TARGET := iphone:clang:latest:14.0
ARCHS = arm64

TWEAK_NAME = YTLanguage

YTLanguage_FILES = Tweak.x $(wildcard Sources/Core/*.m) $(wildcard Sources/Services/*.m) \
	$(wildcard Sources/HostAdapter/*.m) $(wildcard Sources/UI/*.m)
YTLanguage_LIBRARIES = sqlite3
YTL_VERSION := $(strip $(shell cat VERSION))
YTLanguage_CFLAGS = -fobjc-arc -DYTL_VERSION=\"$(YTL_VERSION)\"
YTLanguage_FRAMEWORKS = UIKit Foundation Security
# Sideloaded (ESign) hosts have no CydiaSubstrate; use the ObjC-runtime Logos generator.
YTLanguage_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
