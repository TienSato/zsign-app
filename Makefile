NAME := zsignapp
PLATFORM := iphoneos
SCHEMES := zsignapp
TMP := $(TMPDIR)/$(NAME)
STAGE := $(TMP)/stage
APP := $(TMP)/Build/Products/Release-$(PLATFORM)
PROJECT_DIR := $(shell pwd)

.PHONY: all clean $(SCHEMES) resolve-packages

all: $(SCHEMES)

clean:
	rm -rf $(TMP)
	rm -rf packages
	rm -rf Payload
	rm -rf .build
	rm -rf .swiftpm

# ⭐ NEW: Resolve packages first in project directory
resolve-packages:
	@echo "🔄 Resolving package dependencies..."
	xcodebuild -resolvePackageDependencies \
		-project zsignapp.xcodeproj
	@echo "✅ Packages resolved"

# ⭐ UPDATED: Add resolve-packages as dependency
$(SCHEMES): resolve-packages
	@echo "🔨 Building $@..."
	xcodebuild \
		-project zsignapp.xcodeproj \
		-scheme "$@" \
		-configuration Release \
		-arch arm64 \
		-sdk $(PLATFORM) \
		-derivedDataPath $(TMP) \
		-skipPackagePluginValidation \
		CODE_SIGNING_ALLOWED=NO \
		ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO
	@echo "📦 Creating IPA..."
	rm -rf Payload
	rm -rf $(STAGE)/
	mkdir -p $(STAGE)/Payload
	mv "$(APP)/$@.app" "$(STAGE)/Payload/$@.app"
	rm -rf "$(STAGE)/Payload/$@.app/_CodeSignature"
	ln -sf "$(STAGE)/Payload" Payload
	mkdir -p packages
	cd $(STAGE) && zip -r9 "$(CURDIR)/packages/$@.ipa" Payload
	@echo "✅ IPA created: packages/$@.ipa"