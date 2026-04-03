APP_NAME := Statify
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS := $(APP_BUNDLE)/Contents
DMG_NAME := $(BUILD_DIR)/$(APP_NAME).dmg

.PHONY: app install dmg clean uninstall

app:
	swift build -c release
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/release/$(APP_NAME) $(CONTENTS)/MacOS/
	cp Sources/Statify/Info.plist $(CONTENTS)/
	xcrun actool Sources/Statify/Assets.xcassets \
		--compile $(CONTENTS)/Resources \
		--platform macosx \
		--minimum-deployment-target 13.0 \
		--app-icon AppIcon \
		--output-partial-info-plist /dev/null 2>/dev/null || true
	@if [ -d .build/release/Statify_Statify.bundle ]; then \
		cp -r .build/release/Statify_Statify.bundle $(CONTENTS)/Resources/; \
	fi
	@echo "Built $(APP_BUNDLE)"

install: app
	cp -r $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

dmg: app
	rm -f $(DMG_NAME)
	mkdir -p $(BUILD_DIR)/dmg
	cp -r $(APP_BUNDLE) $(BUILD_DIR)/dmg/
	ln -sf /Applications $(BUILD_DIR)/dmg/Applications
	hdiutil create $(DMG_NAME) \
		-volname "$(APP_NAME)" \
		-srcfolder $(BUILD_DIR)/dmg \
		-ov -format UDZO
	rm -rf $(BUILD_DIR)/dmg
	@echo "Created $(DMG_NAME)"

clean:
	rm -rf $(BUILD_DIR) .build

uninstall:
	rm -rf /Applications/$(APP_NAME).app
	@echo "Removed /Applications/$(APP_NAME).app"
