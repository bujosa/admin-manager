APP_NAME = AdminManager
XCODEBUILD_FLAGS ?=
WORKSPACE = $(APP_NAME).xcworkspace
SCHEME = $(APP_NAME)-Workspace
BUILD_DIR = .build_output
EXECUTABLE_DIR = executables

.PHONY: install generate build run release dmg clean edit help

help:
	@echo "Available targets:"
	@echo "  install  - Install dependencies with tuist"
	@echo "  generate - Generate Xcode project"
	@echo "  build    - Build debug version"
	@echo "  run      - Build and run the app"
	@echo "  release  - Build release version"
	@echo "  dmg      - Create DMG installer"
	@echo "  clean    - Clean all build artifacts"
	@echo "  edit     - Edit Tuist manifest"

install:
	tuist install

generate:
	tuist generate --no-open

build: generate
	xcodebuild -workspace $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination 'platform=macOS' \
		$(XCODEBUILD_FLAGS) \
		-derivedDataPath $(BUILD_DIR) \
		build

run: build
	@open $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app

release: generate
	xcodebuild -workspace $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'platform=macOS' \
		$(XCODEBUILD_FLAGS) \
		-derivedDataPath $(BUILD_DIR) \
		build

dmg: release
	@mkdir -p $(EXECUTABLE_DIR)
	@rm -f $(EXECUTABLE_DIR)/$(APP_NAME).dmg
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app \
		-ov -format UDZO \
		$(EXECUTABLE_DIR)/$(APP_NAME).dmg
	@echo "DMG created at $(EXECUTABLE_DIR)/$(APP_NAME).dmg"

clean:
	rm -rf $(BUILD_DIR)
	rm -rf .build
	rm -rf Derived
	rm -rf $(WORKSPACE)
	rm -rf $(APP_NAME).xcodeproj
	rm -rf $(EXECUTABLE_DIR)

edit:
	tuist edit
