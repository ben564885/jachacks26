.PHONY: build test app run demo install clean

# Build the debug binary.
build:
	swift build

test:
	swift test

# Assemble the signed .app bundle (LSUIElement, launch-at-login capable).
app:
	@./Scripts/bundle.sh

# Run the bundled app.
run: app
	@open ".build/Synqit Notch.app"

# Run the debug binary against a local Jac server (make -C .. serve) without
# touching ~/.synqit or your keychain. The Node mock backend this used to point
# at is gone -- NotchSocket in ../notchsocket.jac serves the same wire contract.
demo: build
	@SYNQIT_SERVER_URL=ws://127.0.0.1:8080/ws/NotchSocket \
	 SYNQIT_DEV_ID=dev_ben \
	 SYNQIT_TOKEN=dev-token \
	 ./.build/debug/SynqitNotch

install: app
	@rm -rf "/Applications/Synqit Notch.app"
	@cp -R ".build/Synqit Notch.app" /Applications/
	@echo "Installed to /Applications/Synqit Notch.app"

clean:
	swift package clean
	@rm -rf ".build/Synqit Notch.app"
