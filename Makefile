APP_NAME := KeySwapo
BUNDLE_ID := com.leonardoramirezr.keyswapo
BUILD_DIR := build
MIN_MACOS := 15.0
ARCH ?= $(shell uname -m)

build:
	bash build.sh

# Unit tests of the platform-independent logic in src/Core.
test:
	mkdir -p "$(BUILD_DIR)"
	xcrun swiftc -target $(ARCH)-apple-macos$(MIN_MACOS) -o "$(BUILD_DIR)/core-tests" src/Core/*.swift tests/*.swift
	"./$(BUILD_DIR)/core-tests"

# Validates a configuration: make check [CONFIG=examples/pipe-to-underscore.json]
check: build
	"$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" --check $(CONFIG)

run: build
	-pkill -x "$(APP_NAME)"
	open "$(BUILD_DIR)/$(APP_NAME).app"

install: build
	-pkill -x "$(APP_NAME)"
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(BUILD_DIR)/$(APP_NAME).app" /Applications/
	open "/Applications/$(APP_NAME).app"

# Forgets the Accessibility permission, e.g. after a rebuild changed the ad hoc signature.
reset-permissions:
	tccutil reset Accessibility $(BUNDLE_ID)

clean:
	rm -rf "$(BUILD_DIR)"

.PHONY: build test check run install reset-permissions clean
