# Jools Makefile
# iOS client for Google's Jules coding agent

PRODUCT_NAME := Jools
SCHEME := Jools
JOOLSKIT_PATH := JoolsKit
DESTINATION := "platform=iOS Simulator,name=iPhone 16 Pro"

.PHONY: all help build test clean xcode format lint kit-build kit-test kit-clean setup

all: build

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ============================================================================
# Setup
# ============================================================================

setup: ## Initial project setup (resolve dependencies)
	@echo "Resolving JoolsKit dependencies..."
	cd $(JOOLSKIT_PATH) && swift package resolve
	@echo "Setup complete!"

# ============================================================================
# JoolsKit (Swift Package)
# ============================================================================

kit-build: ## Build JoolsKit package
	cd $(JOOLSKIT_PATH) && swift build

kit-test: ## Run JoolsKit tests
	cd $(JOOLSKIT_PATH) && swift test

kit-clean: ## Clean JoolsKit build artifacts
	cd $(JOOLSKIT_PATH) && swift package clean

kit-update: ## Update JoolsKit dependencies
	cd $(JOOLSKIT_PATH) && swift package update

# ============================================================================
# iOS App
# ============================================================================

xcode: ## Open the project in Xcode
	open $(PRODUCT_NAME).xcodeproj

build: kit-build ## Build the iOS app for Simulator
	xcodebuild -scheme $(SCHEME) -destination $(DESTINATION) build

test: kit-test ## Run all tests (JoolsKit + iOS app)
	xcodebuild -scheme $(SCHEME) -destination $(DESTINATION) test

clean: kit-clean ## Clean all build artifacts
	xcodebuild -scheme $(SCHEME) clean 2>/dev/null || true
	rm -rf DerivedData
	rm -rf .build

# ============================================================================
# Code Quality
# ============================================================================

format: ## Format code (requires swift-format)
	swift-format format -i -r Jools $(JOOLSKIT_PATH)/Sources $(JOOLSKIT_PATH)/Tests

lint: ## Lint code (requires swiftlint)
	swiftlint

lint-fix: ## Auto-fix lint issues where possible
	swiftlint --fix

# ============================================================================
# Documentation
# ============================================================================

docs: ## Generate documentation (requires swift-docc)
	cd $(JOOLSKIT_PATH) && swift package generate-documentation

# ============================================================================
# Git Helpers
# ============================================================================

status: ## Show git status
	@git status -s

diff: ## Show git diff
	@git diff

# ============================================================================
# CI/CD
# ============================================================================

ci-test: ## Run tests in CI environment
	set -o pipefail && xcodebuild -scheme $(SCHEME) \
		-destination $(DESTINATION) \
		-resultBundlePath TestResults.xcresult \
		test | xcpretty

ci-build: ## Build for CI (release configuration)
	xcodebuild -scheme $(SCHEME) \
		-destination $(DESTINATION) \
		-configuration Release \
		build
