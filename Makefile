APP_NAME := KeySwapo
BUNDLE_ID := com.leonardoramirezr.keyswapo
BUILD_DIR := build
MIN_MACOS := 15.0
ARCH ?= $(shell uname -m)
SWIFTC := xcrun swiftc -target $(ARCH)-apple-macos$(MIN_MACOS)

build:
	bash build.sh

# Unit tests of src/Core, then the key code assumptions checked against Apple's layouts.
test:
	mkdir -p "$(BUILD_DIR)"
	$(SWIFTC) -o "$(BUILD_DIR)/core-tests" src/Core/*.swift tests/*.swift
	"./$(BUILD_DIR)/core-tests"
	$(SWIFTC) -o "$(BUILD_DIR)/layout-tests" src/Core/*.swift src/App/KeyboardLayout.swift tests/layout/main.swift
	"./$(BUILD_DIR)/layout-tests"

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
