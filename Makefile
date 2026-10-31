# Shelf -- the week's Russian videos, chosen by Claude, and the desk around
# them, for the Mac Pro (OS X 10.9). (Russian Shelf until 2026-10-30.)
#
# One window: about twelve videos, in Claude's order, each with its
# thumbnail, length and how far it's been watched. Clicking one plays it in a
# plain player with Russian subtitles to reveal a line at a time. The list
# arrives encrypted and signed in the study repo (Russian/shelf.signed), and
# the videos are downloaded with a bundled yt-dlp. See README.md.
#
# Built like Syllabus: a current Xcode toolchain, linked against the real
# Mac OS X 10.9 SDK in ~/Developer/SDKs, manual retain/release, no
# third-party code in the app itself. The bundled tools (Python, yt-dlp,
# ffmpeg, QuickJS) are in Deps/, built or checked for 10.9 by the scripts
# there.
#
#   make            build build/Shelf.app
#   make run        build and open it (on ~/Study, or StudyFolder in its defaults)
#   make test       the model: crypto, shelves, subtitles, rotation, yt-dlp
#                   command lines, reports, real git (under Rosetta)
#   make tlstest    the bundled Python and yt-dlp check certificates (needs
#                   the network)
#   make shots      render the shelf and the player to build/shots
#   make verify     check the app and every bundled binary are Mavericks-compatible
#   make analyze    clang static analyser; any finding fails
#   make dist       all of the above, then "Shelf.zip"
#   make shelfsign  build/shelfsign, for the MacBook (code-signed: see README)
#   make keys       once: make the signing key and Sources/RSKeys.c
#   make icon       regenerate the icon from Tools/mkicon.m
#   make clean

APP      := Shelf
NAME     := Shelf
BUILD    := build
OBJ      := $(BUILD)/obj
BUNDLE   := $(BUILD)/$(APP).app
CONTENTS := $(BUNDLE)/Contents
MACOS    := $(CONTENTS)/MacOS
RES      := $(CONTENTS)/Resources
ICON     := Resources/$(APP).icns
comma    := ,

CC       := $(shell xcrun -f clang)
HOST_SDK := $(shell xcrun --show-sdk-path)
SDK_10_9 := $(HOME)/Developer/SDKs/MacOSX10.9.sdk
SDK      ?= $(if $(wildcard $(SDK_10_9)/SDKSettings.plist),$(SDK_10_9),$(HOST_SDK))
MIN      := 10.9

# The 10.9 SDK's libraries are Mach-O stubs, which today's linker warns about
# once per library while using them correctly. Quiet only for that SDK.
LDQUIET  := $(if $(findstring 10.9,$(notdir $(SDK))),-Wl$(comma)-w)

AVAILABILITY_CFLAGS := $(shell \
	printf '' | $(CC) -x objective-c -fsyntax-only -Werror \
	  -Wunguarded-availability -Wunguarded-availability-new - \
	  >/dev/null 2>&1 && \
	printf '%s' '-Werror=unguarded-availability -Werror=unguarded-availability-new')

# Manual retain/release: ARC at a 10.9 target needs libarclite, which current
# toolchains no longer ship. -march=core2 as in the other Mavericks projects.
COMMON := -arch x86_64 -march=core2 -mmacosx-version-min=$(MIN) -isysroot "$(SDK)" \
          -Os -fno-common -fvisibility=hidden \
          -Wall -Wextra -Wno-unused-parameter $(AVAILABILITY_CFLAGS) -Wno-deprecated-declarations \
          -ISources
CFLAGS    := $(COMMON) -std=gnu99
OBJCFLAGS := $(COMMON) -fno-objc-arc -fobjc-exceptions -Wno-objc-missing-property-synthesis
LDBASE    := -arch x86_64 -mmacosx-version-min=$(MIN) -isysroot "$(SDK)" -Wl,-dead_strip $(LDQUIET)
FRAMEWORKS := -framework Cocoa -framework AVKit -framework AVFoundation -framework CoreMedia \
              -framework Security -framework CoreServices -lsqlite3

MODEL_SRC := Sources/RSDate.c Sources/RSKeys.c Sources/RSCrypto.m Sources/RSShelf.m Sources/RSSubtitles.m \
             Sources/RSProcess.m Sources/RSSync.m Sources/RSLibrary.m Sources/RSDownloader.m Sources/RSReport.m \
             Sources/RSLines.m Sources/RSClip.m Sources/RSDictionary.m Sources/RSClips.m Sources/RSSay.m \
             Sources/RSSyncFolder.m Sources/RSMerge.m Sources/RSSyncManager.m
VIEW_SRC  := Sources/RSStyle.m Sources/RSShelfView.m Sources/RSPlayer.m Sources/RSReview.m Sources/RSSayWindow.m Sources/RSController.m \
             Sources/RSSelfTest.m
APP_SRC   := $(MODEL_SRC) $(VIEW_SRC) Sources/main.m

obj = $(patsubst Sources/%,$(OBJ)/%.o,$(1))
MODEL_OBJ := $(call obj,$(MODEL_SRC))
VIEW_OBJ  := $(call obj,$(VIEW_SRC))
APP_OBJ   := $(call obj,$(APP_SRC))

# What the bundle carries besides the app (Deps/README.md says where each
# comes from).
DEPS      := Deps/python3/bin/python3.14 Deps/yt-dlp Deps/ffmpeg Deps/qjs
YTDLP_VERSION = $(shell unzip -p Deps/yt-dlp yt_dlp/version.py 2>/dev/null | sed -n "s/^__version__ = '\(.*\)'/\1/p")

.PHONY: all run test tlstest shots verify analyze dist icon clean shelfsign keys dict

all: $(BUNDLE)

Sources/RSKeys.c:
	@echo "Sources/RSKeys.c is missing: the keys are made once, with 'make keys' (see README)." >&2
	@exit 1

$(OBJ)/%.c.o: Sources/%.c Makefile
	@mkdir -p $(dir $@)
	@echo "  compile  $<"
	@$(CC) $(CFLAGS) -MMD -MP -MF $(@:.o=.d) -c $< -o $@

$(OBJ)/%.m.o: Sources/%.m Makefile
	@mkdir -p $(dir $@)
	@echo "  compile  $<"
	@$(CC) $(OBJCFLAGS) -MMD -MP -MF $(@:.o=.d) -c $< -o $@

-include $(wildcard $(OBJ)/*.d)

$(MACOS)/$(APP): $(APP_OBJ)
	@mkdir -p $(MACOS)
	@echo "  link     $@"
	@$(CC) $(LDBASE) $(FRAMEWORKS) $^ -o $@
	@strip -x $@

# The dictionary (RSDictionary.h): built once from OpenRussian's CSVs and the
# RNC frequency list with `make dict DICT_SRC=<folder> DICT_FREQ=<file>`, and
# kept in the repo so every Mac can build the bundle.
DICT      := Resources/dict.sqlite
DICT_SRC  ?=
DICT_FREQ ?=

dict:
	@test -n "$(DICT_SRC)" || { echo "make dict DICT_SRC=<folder with nouns.csv ...> DICT_FREQ=<freqrnc2011.csv>" >&2; exit 1; }
	@python3 -I Tools/mkdict.py "$(DICT_SRC)" "$(DICT_FREQ)" $(DICT)

$(BUNDLE): $(MACOS)/$(APP) Resources/Info.plist Resources/shelf-ssh Resources/selftest.signed $(ICON) $(DEPS) $(DICT)
	@mkdir -p $(RES)
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :RSBundledYtDlpVersion string $(YTDLP_VERSION)" $(CONTENTS)/Info.plist
	@printf 'APPL????' > $(CONTENTS)/PkgInfo
	@cp $(ICON) $(RES)/$(APP).icns
	@cp Resources/shelf-ssh Resources/selftest.signed $(DICT) $(RES)/
	@chmod 755 $(RES)/shelf-ssh
	@rm -rf $(RES)/python3 $(RES)/LICENSES
	@ditto Deps/python3 $(RES)/python3
	@cp Deps/yt-dlp Deps/ffmpeg Deps/qjs $(RES)/
	@chmod 755 $(RES)/ffmpeg $(RES)/qjs
	@mkdir -p $(RES)/LICENSES && cp Deps/LICENSES/* Deps/python3/LICENSES/* $(RES)/LICENSES/
	@touch $(BUNDLE)
	@echo "  built    $(BUNDLE) (yt-dlp $(YTDLP_VERSION))"

run: $(BUNDLE)
	@open $(BUNDLE)

# ---- Tests -----------------------------------------------------------------
#
# Built for the shipping target like everything else; on an Apple silicon
# host they run under Rosetta, the nearest thing to the Mac Pro's Intel CPU
# this machine has.
SUITE := $(BUILD)/rssuite
SHOTS := $(BUILD)/rsshots
NOW   ?= 2026-10-14 20:30

$(SUITE): Tests/rssuite.m Tests/rssuite-sync.m $(MODEL_OBJ)
	@echo "  compile  Tests/rssuite.m"
	@$(CC) $(OBJCFLAGS) -c Tests/rssuite.m -o $(OBJ)/rssuite.o
	@$(CC) $(LDBASE) -framework Foundation -framework Security -framework AVFoundation -framework CoreMedia -framework CoreServices \
	   -lsqlite3 $(MODEL_OBJ) $(OBJ)/rssuite.o -o $@

test: $(SUITE)
	@$(SUITE) "$(CURDIR)/Tests/Fixtures"

# Needs the network: certificates are checked against certifi's list, a
# self-signed server is refused, and yt-dlp's self-update works with checks
# on.
tlstest: $(BUNDLE)
	@/bin/sh Tests/tlstest.sh "$(CURDIR)/$(RES)" "$(CURDIR)/$(BUILD)/tlstest"

$(SHOTS): Tests/rsshots.m $(MODEL_OBJ) $(VIEW_OBJ)
	@echo "  compile  Tests/rsshots.m"
	@$(CC) $(OBJCFLAGS) -c Tests/rsshots.m -o $(OBJ)/rsshots.o
	@$(CC) $(LDBASE) $(FRAMEWORKS) $(MODEL_OBJ) $(VIEW_OBJ) $(OBJ)/rsshots.o -o $@

shots: $(SHOTS)
	@rm -rf $(BUILD)/shots
	@mkdir -p $(BUILD)/shots
	@RUSSIAN_SHELF_NOW="$(NOW)" $(SHOTS) "$(CURDIR)/Tests/Fixtures" "$(CURDIR)/$(BUILD)/shots"

# ---- Mavericks compatibility ---------------------------------------------
REQUIRE_SDK ?= any

verify: $(BUNDLE)
	@echo "== Mach-O compatibility check =="
	@plutil -lint $(CONTENTS)/Info.plist >/dev/null || { echo "FAIL: Info.plist"; exit 1; }
	@test -f $(RES)/$(APP).icns || { echo "FAIL: icon missing from bundle"; exit 1; }
	@test -x $(RES)/shelf-ssh || { echo "FAIL: shelf-ssh missing or not executable"; exit 1; }
	@m=$(MACOS)/$(APP); \
	  archs="$$(lipo -archs $$m)"; \
	  [ "$$archs" = "x86_64" ] || { echo "FAIL: architectures: $$archs"; exit 1; }; \
	  min="$$(otool -l $$m | awk '/LC_VERSION_MIN_MACOSX/{getline; getline; print $$2; exit}')"; \
	  [ "$$min" = "10.9" ] || { echo "FAIL: minimum OS is '$$min'"; exit 1; }; \
	  sdk="$$(otool -l $$m | awk '/LC_VERSION_MIN_MACOSX/{getline; getline; getline; print $$2; exit}')"; \
	  if [ "$(REQUIRE_SDK)" != "any" ] && [ "$$sdk" != "$(REQUIRE_SDK)" ]; then \
	    echo "FAIL: built against SDK $$sdk, not $(REQUIRE_SDK)"; exit 1; fi; \
	  echo "   x86_64, minimum OS $$min, built against SDK $$sdk"; \
	  if otool -l $$m | grep -q LC_BUILD_VERSION; then echo "FAIL: LC_BUILD_VERSION present"; exit 1; fi; \
	  if otool -l $$m | grep -q LC_DYLD_CHAINED_FIXUPS; then echo "FAIL: chained fixups"; exit 1; fi; \
	  if otool -l $$m | grep -q LC_DYLD_EXPORTS_TRIE; then echo "FAIL: exports trie load command"; exit 1; fi; \
	  if otool -l $$m | grep -q LC_RPATH; then echo "FAIL: LC_RPATH present"; exit 1; fi; \
	  otool -L $$m | tail -n +2 | sed 's/^/   /'; \
	  otool -L $$m | tail -n +2 | awk '{print $$1}' | \
	    grep -vE '^/System/Library/Frameworks/(Cocoa|AppKit|Foundation|CoreFoundation|ApplicationServices|CoreServices|CoreGraphics|AVKit|AVFoundation|CoreMedia|QuartzCore|Security)\.framework/Versions/[A-Z]/[A-Za-z]+$$' | \
	    grep -vE '^/usr/lib/(libSystem\.B|libobjc\.A|libsqlite3)\.dylib$$' | \
	    (! grep .) || { echo "FAIL: unexpected dylib above"; exit 1; }
	@# A current SDK binds many Foundation classes to CoreFoundation, where they
	@# live today, and a name 10.9's CoreFoundation lacks stops the app
	@# launching (see Nightlatch's Makefile). Built against the 10.9 SDK, every
	@# name bound to CoreFoundation is checked against that SDK's own
	@# CoreFoundation, which lists what 10.9.5 exports. Otherwise only names
	@# proven on 10.9.5 by Postview (2026-09-05) may be bound there.
	@names="$$(nm -um $(MACOS)/$(APP) | grep 'from CoreFoundation' | grep -oE '_(OBJC_[A-Z]+_\$$_)?NS[A-Za-z]+' | sort -u)"; \
	if [ -f "$(SDK)/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation" ] && \
	   [ "$$(/usr/libexec/PlistBuddy -c 'Print :Version' "$(SDK)/SDKSettings.plist" 2>/dev/null)" = "10.9" ]; then \
	  exported="$$(nm -gU "$(SDK)/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation" 2>/dev/null | awk '{print $$3}')"; \
	  for n in $$names; do printf '%s\n' "$$exported" | grep -qxF "$$n" || { echo "FAIL: $$n is bound to CoreFoundation, which 10.9 doesn't export it from"; exit 1; }; done; \
	  echo "   Foundation names bound to CoreFoundation: all exported by 10.9's CoreFoundation"; \
	else \
	  printf '%s\n' "$$names" | grep -vxE '_NSRunLoopCommonModes|_OBJC_CLASS_\$$_NS(Array|Date|Dictionary|MutableArray|MutableData|MutableDictionary|MutableSet|RunLoop|Timer|URL|UserDefaults)' | \
	    (! grep .) || { echo "FAIL: Foundation names bound to CoreFoundation that 10.9 may not have (above)"; exit 1; }; \
	  echo "   Foundation names bound to CoreFoundation: only those proven on 10.9.5"; \
	fi
	@otool -hv $(MACOS)/$(APP) | grep -q EXECUTE || { echo "FAIL: not an executable"; exit 1; }
	@# The app opens nothing it's handed: no document or URL types.
	@! /usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes' $(CONTENTS)/Info.plist >/dev/null 2>&1 || { echo "FAIL: document types in Info.plist"; exit 1; }
	@! /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' $(CONTENTS)/Info.plist >/dev/null 2>&1 || { echo "FAIL: URL types in Info.plist"; exit 1; }
	@echo "   no document or URL types"
	@# Certificates are always checked.
	@! grep -aq 'no-check-certificate' $(MACOS)/$(APP) || { echo "FAIL: the app mentions --no-check-certificates"; exit 1; }
	@echo "   never --no-check-certificates"
	@# What the bundle runs that wasn't built here: every library it loads and
	@# every symbol it imports must exist on 10.9 (Tools/check109.sh).
	@test -z "$$(find $(RES) -name 'deno*')" || { echo "FAIL: deno is bundled; it can't run on 10.9"; exit 1; }
	@echo "== Bundled tools: Python, its modules, ffmpeg, QuickJS =="
	@find $(RES) -type f \( -name '*.so' -o -name python3.14 -o -name ffmpeg -o -name qjs \) -print0 | \
	  xargs -0 /bin/sh Tools/check109.sh "$(SDK_10_9)" || { echo "FAIL: a bundled binary needs more than 10.9 has"; exit 1; }
	@echo "   $$(find $(RES) -type f \( -name '*.so' -o -name python3.14 -o -name ffmpeg -o -name qjs \) | wc -l | tr -d ' ') binaries: every library and symbol they use is in 10.9"
	@echo "OK"

analyze:
	@echo "== Clang static analysis =="
	@mkdir -p $(BUILD)
	@log=$(BUILD)/analyze.log; : > $$log; status=0; \
	for f in $(filter %.c,$(APP_SRC)); do \
	  $(CC) $(CFLAGS) --analyze -Xanalyzer -analyzer-output=text $$f -o /dev/null >> $$log 2>&1 || status=1; \
	done; \
	for f in $(filter %.m,$(APP_SRC)); do \
	  $(CC) $(OBJCFLAGS) --analyze -Xanalyzer -analyzer-output=text $$f -o /dev/null >> $$log 2>&1 || status=1; \
	done; \
	if grep -qE '(warning|error):' $$log; then cat $$log; echo "FAIL: analyser findings"; exit 1; fi; \
	[ $$status -eq 0 ] || { cat $$log; echo "FAIL: analyser did not run"; exit 1; }
	@echo "OK"

# ---- Distribution ----------------------------------------------------------

dist: all verify analyze test tlstest
	@rm -rf $(BUILD)/dist "$(NAME).zip"
	@mkdir -p $(BUILD)/dist
	@ditto $(BUNDLE) "$(BUILD)/dist/$(NAME).app"
	@cp README.md $(BUILD)/dist/README.md
	@xattr -cr $(BUILD)/dist 2>/dev/null || true
	@cd $(BUILD)/dist && ditto -c -k --norsrc --noextattr --noqtn --noacl . "../../$(NAME).zip"
	@echo "  packaged $(NAME).zip ($$(du -h "$(NAME).zip" | cut -f1); the app is $$(du -sh "$(BUILD)/dist/$(NAME).app" | cut -f1) unzipped)"

# ---- shelfsign, for the MacBook ----------------------------------------------
#
# Built natively from the app's own shelf and crypto code, so it seals exactly
# what the app opens. Code-signed with a stable identifier: the signing key's
# keychain entry trusts "com.russianshelf.shelfsign" signed by this
# certificate, so rebuilding it doesn't bring up a keychain dialog.
SHELFSIGN := $(BUILD)/shelfsign
SHELFSIGN_SRC := Tools/shelfsign.m Sources/RSDate.c Sources/RSCrypto.m Sources/RSShelf.m
SHELFSIGN_IDENTITY ?= Apple Development
HOSTFLAGS := -isysroot "$(HOST_SDK)" -fno-objc-arc -O1 -Wall -Wno-deprecated-declarations -ISources

$(SHELFSIGN): $(SHELFSIGN_SRC) Sources/RSKeys.c Sources/RSShelf.h Sources/RSCrypto.h Sources/RSKeys.h
	@mkdir -p $(BUILD)
	@echo "  compile  Tools/shelfsign.m (host)"
	@$(CC) $(HOSTFLAGS) $(SHELFSIGN_SRC) Sources/RSKeys.c -framework Foundation -framework Security -o $@
	@codesign -s "$(SHELFSIGN_IDENTITY)" --identifier com.russianshelf.shelfsign -f $@ 2>/dev/null || \
	  { echo "FAIL: couldn't sign shelfsign with '$(SHELFSIGN_IDENTITY)' (set SHELFSIGN_IDENTITY)"; rm -f $@; exit 1; }

shelfsign: $(SHELFSIGN)

# Once, ever: makes the signing key in the login keychain and writes
# Sources/RSKeys.c (the AES key and the public key). Refuses if either exists.
keys:
	@test ! -f Sources/RSKeys.c || { echo "Sources/RSKeys.c exists: the keys are made once."; exit 1; }
	@mkdir -p $(BUILD)
	@printf '#include "RSKeys.h"\nconst unsigned char RSKeyAES[32];\nconst unsigned char RSKeyPublic[91];\n' > $(BUILD)/RSKeysPlaceholder.c
	@$(CC) $(HOSTFLAGS) $(SHELFSIGN_SRC) $(BUILD)/RSKeysPlaceholder.c -framework Foundation -framework Security -o $(BUILD)/shelfsign-keygen
	@codesign -s "$(SHELFSIGN_IDENTITY)" --identifier com.russianshelf.shelfsign -f $(BUILD)/shelfsign-keygen 2>/dev/null
	@$(BUILD)/shelfsign-keygen keygen Sources/RSKeys.c
	@rm -f $(BUILD)/shelfsign-keygen $(BUILD)/RSKeysPlaceholder.c

# ---- Icon ------------------------------------------------------------------
MKICON := $(BUILD)/mkicon

$(MKICON): Tools/mkicon.m
	@mkdir -p $(BUILD)
	@echo "  compile  Tools/mkicon.m (host)"
	@$(CC) -isysroot "$(HOST_SDK)" -fobjc-arc -O2 -Wall -Wno-deprecated-declarations -framework Cocoa \
	   Tools/mkicon.m -o $@

$(ICON):
	@$(MAKE) --no-print-directory icon

icon: $(MKICON)
	@rm -rf $(BUILD)/$(APP).iconset
	@$(MKICON) $(BUILD)/$(APP).iconset
	@iconutil -c icns $(BUILD)/$(APP).iconset -o $(ICON)
	@echo "  wrote    $(ICON)"

clean:
	@rm -rf $(BUILD)
