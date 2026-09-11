ifndef SDK_VERSION
SDK_VERSION = 18.6
endif

export TARGET = iphone:clang:$(SDK_VERSION):15.0
export SDK_PATH = $(THEOS)/sdks/iPhoneOS$(SDK_VERSION).sdk/
export SYSROOT = $(SDK_PATH)
export ARCHS = arm64

TWEAK_NAME ?= uYouEnhanced
DISPLAY_NAME ?= YouTube
BUNDLE_ID ?= com.google.ios.youtube

ifndef YOUTUBE_VERSION
YOUTUBE_VERSION = 21.20.4
endif
ifndef UYOU_VERSION
UYOU_VERSION = 3.0.4.1
endif
PACKAGE_NAME = $(TWEAK_NAME)
PACKAGE_VERSION = $(YOUTUBE_VERSION)-$(UYOU_VERSION)

$(TWEAK_NAME)_FILES := $(wildcard Sources/*.xm) $(wildcard Sources/*.x) $(wildcard Sources/*.m) Sources/MediaKit/UYTMediaKit.m
$(info [UYT] compile list: $($(TWEAK_NAME)_FILES))
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation AVFoundation AVKit Photos Accelerate CoreMotion GameController VideoToolbox Security MediaPlayer
$(TWEAK_NAME)_LIBRARIES = bz2 c++ iconv z sqlite3
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-but-set-variable -DTWEAK_VERSION=\"$(PACKAGE_VERSION)\"

export libcolorpicker_ARCHS = arm64
export libFLEX_ARCHS = arm64
export Alderis_XCODEOPTS = LD_DYLIB_INSTALL_NAME=@rpath/Alderis.framework/Alderis
export Alderis_XCODEFLAGS = DYLIB_INSTALL_NAME_BASE=/Library/Frameworks BUILD_LIBRARY_FOR_DISTRIBUTION=YES ARCHS="$(ARCHS)"
export libcolorpicker_LDFLAGS = -F$(TARGET_PRIVATE_FRAMEWORK_PATH) -install_name @rpath/libcolorpicker.dylib
export ADDITIONAL_CFLAGS = -I$(THEOS_PROJECT_DIR)/Tweaks/RemoteLog -I$(THEOS_PROJECT_DIR)/Tweaks

ifneq ($(JAILBROKEN),1)
export DEBUGFLAG = -ggdb -Wno-unused-command-line-argument -L$(THEOS_OBJ_DIR) -F$(_THEOS_LOCAL_DATA_DIR)/$(THEOS_OBJ_DIR_NAME)/install/Library/Frameworks
MODULES = jailed
endif

$(TWEAK_NAME)_INJECT_DYLIBS = \
	Tweaks/uYou/Library/MobileSubstrate/DynamicLibraries/uYou.dylib \
	$(THEOS_OBJ_DIR)/libFLEX.dylib \
	$(THEOS_OBJ_DIR)/YTABConfig.dylib \
	$(THEOS_OBJ_DIR)/YTIcons.dylib \
	$(THEOS_OBJ_DIR)/YouGroupSettings.dylib \
	$(THEOS_OBJ_DIR)/YouLoop.dylib \
	$(THEOS_OBJ_DIR)/YouMute.dylib \
	$(THEOS_OBJ_DIR)/YouPiP.dylib \
	$(THEOS_OBJ_DIR)/YouQuality.dylib \
	$(THEOS_OBJ_DIR)/YouSlider.dylib \
	$(THEOS_OBJ_DIR)/YouSpeed.dylib \
	$(THEOS_OBJ_DIR)/YouTimeStamp.dylib \
	$(THEOS_OBJ_DIR)/YouTubeDislikesReturn.dylib \
	$(THEOS_OBJ_DIR)/DontEatMyContent.dylib \
	$(THEOS_OBJ_DIR)/YTHoldForSpeed.dylib \
	$(THEOS_OBJ_DIR)/YTVideoOverlay.dylib \
	$(THEOS_OBJ_DIR)/YTweaks.dylib

ifeq ($(SPONSORBLOCK_ENABLED),1)
$(TWEAK_NAME)_INJECT_DYLIBS += $(THEOS_OBJ_DIR)/iSponsorBlock.dylib
endif

ifeq ($(YTUHD_ENABLED),1)
$(TWEAK_NAME)_INJECT_DYLIBS += $(THEOS_OBJ_DIR)/YTUHD.dylib
endif

$(TWEAK_NAME)_EMBED_LIBRARIES = $(THEOS_OBJ_DIR)/libcolorpicker.dylib
$(TWEAK_NAME)_EMBED_FRAMEWORKS = $(_THEOS_LOCAL_DATA_DIR)/$(THEOS_OBJ_DIR_NAME)/install_Alderis.xcarchive/Products/var/jb/Library/Frameworks/Alderis.framework
$(TWEAK_NAME)_EMBED_BUNDLES = $(wildcard Bundles/*.bundle)
$(TWEAK_NAME)_EMBED_EXTENSIONS = $(wildcard Extensions/*.appex)

INSTALL_TARGET_PROCESSES = YouTube
REMOVE_EXTENSIONS = 1
CODESIGN_IPA = 0
FINALPACKAGE = 1

UYOU_PATH = Tweaks/uYou
UYOU_DEB = $(UYOU_PATH)/com.miro.uyou_$(UYOU_VERSION)_iphoneos-arm.deb
UYOU_DYLIB = $(UYOU_PATH)/Library/MobileSubstrate/DynamicLibraries/uYou.dylib
UYOU_BUNDLE = $(UYOU_PATH)/Library/Application\ Support/uYouBundle.bundle
UYOU_URL = https://www.dropbox.com/scl/fi/b7gibc3itf41ydnkhfqhn/com.miro.uyou_3.0.4.1_iphoneos-arm.deb?rlkey=6m0sus20j87setsukhvpyeiuk&st=cpua440m&dl=1

YTUHD_VENDOR_DIR = Tweaks/YTUHD/vendor
YTUHD_DAV1D_SRC = $(YTUHD_VENDOR_DIR)/dav1d
YTUHD_LIBVPX_SRC = $(YTUHD_VENDOR_DIR)/libvpx

ifeq ($(YTUHD_ENABLED),1)
$(shell test -f $(YTUHD_DAV1D_SRC)/meson.build || (echo "Initializing YTUHD vendor submodules..." && cd Tweaks/YTUHD && git submodule update --init --recursive))
endif

.PHONY: ytuhd-vendor-init
ytuhd-vendor-init:
	@echo "Initializing YTUHD vendor submodules..."
	@cd Tweaks/YTUHD && git submodule update --init --recursive

# Target to manually build YTUHD vendor libraries
.PHONY: ytuhd-vendor-build
ytuhd-vendor-build:
	@echo "Building YTUHD vendor libraries..."
	@cd Tweaks/YTUHD && make libvpx dav1d

include $(THEOS)/makefiles/common.mk

ifneq ($(JAILBROKEN),1)
SUBPROJECTS += Tweaks/Alderis Tweaks/DontEatMyContent Tweaks/FLEXing/libflex Tweaks/Return-YouTube-Dislikes Tweaks/YTABConfig Tweaks/YouGroupSettings Tweaks/YTIcons Tweaks/YouLoop Tweaks/YouPiP Tweaks/YouQuality Tweaks/YouSlider Tweaks/YouSpeed Tweaks/YouTimeStamp Tweaks/YTVideoOverlay Tweaks/YTweaks
ifeq ($(SPONSORBLOCK_ENABLED),1)
SUBPROJECTS += Tweaks/iSponsorBlock
endif
ifeq ($(YTUHD_ENABLED),1)
SUBPROJECTS += Tweaks/YTUHD
endif
include $(THEOS_MAKE_PATH)/aggregate.mk
endif

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: internal-clean before-all before-package
internal-clean::
	@rm -rf $(UYOU_PATH)/*

ifneq ($(JAILBROKEN),1)
before-all::
	@if [[ ! -f $(UYOU_DEB) ]]; then \
		if [[ "$(UYOU_VERSION)" == "3.0.4.1" ]]; then \
			$(PRINT_FORMAT_BLUE) "Downloading uYou $(UYOU_VERSION)"; \
		else \
			$(PRINT_FORMAT_BLUE) "Using custom uYou $(UYOU_VERSION) — expecting $(UYOU_DEB)"; \
		fi; \
	fi
before-all::
	@if [[ ! -f $(UYOU_DEB) ]]; then \
		if [[ "$(UYOU_VERSION)" == "3.0.4.1" ]]; then \
			$(PRINT_FORMAT_BLUE) "Downloading uYou $(UYOU_VERSION)"; \
			mkdir -p Tweaks/uYou; \
			curl -s -L -f --retry 3 --retry-delay 5 "$(UYOU_URL)" -o $(UYOU_DEB) || { $(PRINT_FORMAT_ERROR) "Failed to download uYou deb"; exit 1; }; \
		else \
			$(PRINT_FORMAT_BLUE) "Using custom uYou $(UYOU_VERSION) — expecting $(UYOU_DEB)"; \
		fi; \
	fi; \
	if [[ ! -f $(UYOU_DEB) ]]; then \
		$(PRINT_FORMAT_ERROR) "Missing $(UYOU_DEB) — place your custom deb at that path"; exit 1; \
	fi; \
	if [[ ! -f $(UYOU_DYLIB) || ! -d $(UYOU_BUNDLE) ]]; then \
		echo "[DEBUG] Extracting $(UYOU_DEB)..."; \
		mkdir -p Tweaks/uYou; \
		tar -xvf $(UYOU_DEB) -C Tweaks/uYou 2>&1 | head -20; \
		if [[ -f "Tweaks/uYou/data.tar.gz" ]]; then \
			tar -xzf Tweaks/uYou/data.tar.gz -C Tweaks/uYou; \
		elif [[ -f "Tweaks/uYou/data.tar.xz" ]]; then \
			tar -xJf Tweaks/uYou/data.tar.xz -C Tweaks/uYou; \
		else \
			find Tweaks/uYou -name "data.tar*" -exec tar -xf {} -C Tweaks/uYou \; 2>/dev/null || true; \
		fi; \
		if [[ ! -f $(UYOU_DYLIB) ]]; then \
			$(PRINT_FORMAT_ERROR) "Missing dylib at $(UYOU_DYLIB)"; find Tweaks/uYou -name "*.dylib" -o -type d -name "MobileSubstrate"; exit 1; \
		fi; \
		if [[ ! -d $(UYOU_BUNDLE) ]]; then \
			$(PRINT_FORMAT_ERROR) "Missing bundle at $(UYOU_BUNDLE)"; find Tweaks/uYou -name "*.bundle"; exit 1; \
		fi; \
	fi;

else
before-package::
	@mkdir -p $(THEOS_STAGING_DIR)/Library/Application\ Support; cp -r Localizations/uYouPlus.bundle $(THEOS_STAGING_DIR)/Library/Application\ Support/
endif
