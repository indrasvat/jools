# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                Jataayu                                       ║
# ║                    iOS Client for Google's Jules Coding Agent                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ─────────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────────

PRODUCT_NAME     := Jataayu
SCHEME           := Jools
JOOLSKIT_PATH    := JoolsKit
PROJECT          := $(PRODUCT_NAME).xcodeproj
# Simulator name - override with: make sim-run SIMULATOR="iPhone 17 Pro Max"
SIMULATOR        ?= iPhone 17 Pro
DESTINATION      := platform=iOS Simulator,name=$(SIMULATOR)
DEVICE_DEST      := generic/platform=iOS
DERIVED_DATA     := $(HOME)/Library/Developer/Xcode/DerivedData
BUILD_DIR        := .build
COVERAGE_DIR     := $(BUILD_DIR)/coverage
# Screenshot output path - override with: make sim-screenshot SCREENSHOT=/path/to/file.png
SCREENSHOT       ?= /tmp/jataayu_screenshot.png
SCREENSHOT_DIR   ?= $(BUILD_DIR)/screenshots
AXE              := $(shell command -v axe 2>/dev/null)

# Tools
BREW             := $(shell command -v brew 2>/dev/null)
SWIFTLINT        := $(shell command -v swiftlint 2>/dev/null)
SWIFTFORMAT      := $(shell command -v swift-format 2>/dev/null)
XCODEGEN         := $(shell command -v xcodegen 2>/dev/null)
LEFTHOOK         := $(shell command -v lefthook 2>/dev/null)
XCPRETTY         := $(shell command -v xcpretty 2>/dev/null)

# Colors
RESET            := \033[0m
BOLD             := \033[1m
RED              := \033[31m
GREEN            := \033[32m
YELLOW           := \033[33m
BLUE             := \033[34m
MAGENTA          := \033[35m
CYAN             := \033[36m
WHITE            := \033[37m
BG_GREEN         := \033[42m
BG_BLUE          := \033[44m
BG_MAGENTA       := \033[45m

# Icons
CHECK            := ✓
CROSS            := ✗
ARROW            := →
GEAR             := ⚙
PACKAGE          := 📦
ROCKET           := 🚀
BROOM            := 🧹
TEST_ICON        := 🧪
LINT_ICON        := 🔍
BUILD_ICON       := 🔨
HOOK_ICON        := 🪝

.PHONY: all help setup deps check-deps install-deps \
        build build-release build-device test test-app coverage \
        lint lint-fix format clean clean-all \
        xcode generate run \
        kit-build kit-test kit-clean kit-update \
        ci pre-push hooks-install hooks-uninstall \
        ci-build-for-testing ci-test ci-test-unit ci-test-ui ci-package-build ci-unpack-build \
        release \
        status diff log \
        sim-list sim-boot sim-build sim-run sim-install sim-launch sim-kill sim-logs sim-shutdown \
        sim-reload sim-screenshot ui-test sim-ui-smoke sim-screenshot-bundle verify-live-session

.DEFAULT_GOAL := help

# ─────────────────────────────────────────────────────────────────────────────────
# Help
# ─────────────────────────────────────────────────────────────────────────────────

help: ## Show this help
	@echo ""
	@echo "$(BOLD)$(MAGENTA)  ╔═══════════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(BOLD)$(MAGENTA)  ║$(RESET)$(BOLD)                       $(CYAN)Jataayu$(RESET)$(BOLD)                               $(MAGENTA)║$(RESET)"
	@echo "$(BOLD)$(MAGENTA)  ║$(RESET)       $(WHITE)iOS Client for Google's Jules Coding Agent$(RESET)          $(MAGENTA)║$(RESET)"
	@echo "$(BOLD)$(MAGENTA)  ╚═══════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)  Usage:$(RESET) make $(CYAN)<target>$(RESET)"
	@echo ""
	@echo "$(BOLD)$(GREEN)  ─── Setup ────────────────────────────────────────────────────────$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(setup|deps|install|hooks)' | awk 'BEGIN {FS = ":.*?## "}; {printf "    $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BOLD)$(BLUE)  ─── Build ────────────────────────────────────────────────────────$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(build|generate|xcode|run)' | awk 'BEGIN {FS = ":.*?## "}; {printf "    $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BOLD)$(MAGENTA)  ─── Test ─────────────────────────────────────────────────────────$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(test|coverage)' | awk 'BEGIN {FS = ":.*?## "}; {printf "    $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BOLD)$(YELLOW)  ─── Quality ──────────────────────────────────────────────────────$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(lint|format)' | awk 'BEGIN {FS = ":.*?## "}; {printf "    $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BOLD)$(RED)  ─── Clean ────────────────────────────────────────────────────────$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E 'clean' | awk 'BEGIN {FS = ":.*?## "}; {printf "    $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BOLD)$(WHITE)  ─── JoolsKit ─────────────────────────────────────────────────────$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E 'kit-' | awk 'BEGIN {FS = ":.*?## "}; {printf "    $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BOLD)$(CYAN)  ─── CI/CD ────────────────────────────────────────────────────────$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(^ci|^ci-|pre-push)' | awk 'BEGIN {FS = ":.*?## "}; {printf "    $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BOLD)$(GREEN)  ─── Release ──────────────────────────────────────────────────────$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '^release:' | awk 'BEGIN {FS = ":.*?## "}; {printf "    $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BOLD)$(WHITE)  ─── Simulator ────────────────────────────────────────────────────$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E 'sim-' | awk 'BEGIN {FS = ":.*?## "}; {printf "    $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""

# ─────────────────────────────────────────────────────────────────────────────────
# Setup & Dependencies
# ─────────────────────────────────────────────────────────────────────────────────

setup: deps hooks-install generate ## Full project setup (deps + hooks + generate)
	@echo ""
	@echo "$(GREEN)$(CHECK) Project setup complete!$(RESET)"
	@echo "$(CYAN)$(ARROW) Run 'make xcode' to open in Xcode$(RESET)"

deps: check-deps ## Install all dependencies
	@echo "$(GREEN)$(CHECK) All dependencies installed$(RESET)"

check-deps: ## Check and install missing dependencies
	@echo "$(BOLD)$(PACKAGE) Checking dependencies...$(RESET)"
ifndef BREW
	$(error "$(RED)$(CROSS) Homebrew not found. Install from https://brew.sh$(RESET)")
endif
ifndef SWIFTLINT
	@echo "$(YELLOW)$(ARROW) Installing swiftlint...$(RESET)"
	@brew install swiftlint
endif
ifndef XCODEGEN
	@echo "$(YELLOW)$(ARROW) Installing xcodegen...$(RESET)"
	@brew install xcodegen
endif
ifndef LEFTHOOK
	@echo "$(YELLOW)$(ARROW) Installing lefthook...$(RESET)"
	@brew install lefthook
endif
ifndef XCPRETTY
	@echo "$(YELLOW)$(ARROW) Installing xcpretty...$(RESET)"
	@gem install xcpretty 2>/dev/null || sudo gem install xcpretty
endif
	@echo "$(GREEN)$(CHECK) swiftlint: $(shell swiftlint version 2>/dev/null || echo 'installing...')$(RESET)"
	@echo "$(GREEN)$(CHECK) xcodegen: $(shell xcodegen version 2>/dev/null || echo 'installing...')$(RESET)"
	@echo "$(GREEN)$(CHECK) lefthook: $(shell lefthook version 2>/dev/null | head -1 || echo 'installing...')$(RESET)"

install-deps: ## Force reinstall all dependencies
	@echo "$(BOLD)$(PACKAGE) Installing dependencies...$(RESET)"
	brew install swiftlint xcodegen lefthook || true
	gem install xcpretty 2>/dev/null || sudo gem install xcpretty || true
	@echo "$(GREEN)$(CHECK) Dependencies installed$(RESET)"

# ─────────────────────────────────────────────────────────────────────────────────
# Git Hooks (Lefthook)
# ─────────────────────────────────────────────────────────────────────────────────

hooks-install: ## Install git hooks via lefthook
	@echo "$(BOLD)$(HOOK_ICON) Installing git hooks...$(RESET)"
	@command -v lefthook >/dev/null 2>&1 || (echo "$(YELLOW)$(ARROW) Installing lefthook...$(RESET)" && brew install lefthook)
	@lefthook install
	@echo "$(GREEN)$(CHECK) Git hooks installed$(RESET)"

hooks-uninstall: ## Uninstall git hooks
	@echo "$(BOLD)$(HOOK_ICON) Uninstalling git hooks...$(RESET)"
	@lefthook uninstall || true
	@echo "$(GREEN)$(CHECK) Git hooks removed$(RESET)"

# ─────────────────────────────────────────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────────────────────────────────────────

generate: ## Generate Xcode project from project.yml
	@echo "$(BOLD)$(GEAR) Generating Xcode project...$(RESET)"
	@xcodegen generate
	@echo "$(GREEN)$(CHECK) Project generated$(RESET)"

build: kit-build ## Build for simulator (debug)
	@echo "$(BOLD)$(BUILD_ICON) Building $(PRODUCT_NAME) for simulator...$(RESET)"
	@set -o pipefail && xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(DESTINATION)" \
		-configuration Debug \
		build 2>&1 | xcpretty || xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(DESTINATION)" \
		-configuration Debug \
		build
	@echo "$(GREEN)$(CHECK) Build succeeded$(RESET)"

build-release: kit-build ## Build for simulator (release)
	@echo "$(BOLD)$(BUILD_ICON) Building $(PRODUCT_NAME) (release)...$(RESET)"
	@set -o pipefail && xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(DESTINATION)" \
		-configuration Release \
		build 2>&1 | xcpretty || xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(DESTINATION)" \
		-configuration Release \
		build
	@echo "$(GREEN)$(CHECK) Release build succeeded$(RESET)"

build-device: kit-build ## Build for device (requires signing)
	@echo "$(BOLD)$(BUILD_ICON) Building $(PRODUCT_NAME) for device...$(RESET)"
	@xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(DEVICE_DEST)" \
		-configuration Release \
		build
	@echo "$(GREEN)$(CHECK) Device build succeeded$(RESET)"

xcode: ## Open project in Xcode
	@echo "$(BOLD)$(ROCKET) Opening Xcode...$(RESET)"
	@open $(PROJECT)

run: sim-run ## Build and run on simulator (alias for sim-run)

# ─────────────────────────────────────────────────────────────────────────────────
# Test
# ─────────────────────────────────────────────────────────────────────────────────

test: kit-test test-app ## Run all tests
	@echo "$(GREEN)$(CHECK) All tests passed$(RESET)"

test-app: ## Run iOS app tests
	@echo "$(BOLD)$(TEST_ICON) Testing $(PRODUCT_NAME) app...$(RESET)"
	@set -o pipefail && xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(DESTINATION)" \
		-configuration Debug \
		test 2>&1 | xcpretty || xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(DESTINATION)" \
		-configuration Debug \
		test
	@echo "$(GREEN)$(CHECK) App tests passed$(RESET)"

ui-test: ## Run deterministic Jools UI tests
	@echo "$(BOLD)$(TEST_ICON) Running Jools UI tests...$(RESET)"
	@set -o pipefail && xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(DESTINATION)" \
		-configuration Debug \
		-only-testing:JoolsUITests \
		test 2>&1 | xcpretty || xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(DESTINATION)" \
		-configuration Debug \
		-only-testing:JoolsUITests \
		test
	@echo "$(GREEN)$(CHECK) UI tests passed$(RESET)"

coverage: ## Run tests with coverage report
	@echo "$(BOLD)$(TEST_ICON) Running tests with coverage...$(RESET)"
	@mkdir -p $(COVERAGE_DIR)
	@xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(DESTINATION)" \
		-enableCodeCoverage YES \
		-resultBundlePath $(COVERAGE_DIR)/TestResults.xcresult \
		test 2>&1 | xcpretty || true
	@echo "$(GREEN)$(CHECK) Coverage report: $(COVERAGE_DIR)/TestResults.xcresult$(RESET)"

# ─────────────────────────────────────────────────────────────────────────────────
# Code Quality
# ─────────────────────────────────────────────────────────────────────────────────

lint: ## Run SwiftLint on all Swift files
	@echo "$(BOLD)$(LINT_ICON) Linting code...$(RESET)"
	@SL=$$(command -v swiftlint || echo /opt/homebrew/bin/swiftlint); \
	if [ ! -x "$$SL" ]; then \
		echo "$(YELLOW)$(ARROW) swiftlint not found, skipping lint$(RESET)"; \
		exit 0; \
	fi; \
	if "$$SL" lint --quiet; then \
		echo "$(GREEN)$(CHECK) No lint errors$(RESET)"; \
	else \
		echo "$(RED)$(CROSS) Lint errors found$(RESET)"; \
		exit 1; \
	fi

lint-fix: ## Auto-fix lint issues
	@echo "$(BOLD)$(LINT_ICON) Auto-fixing lint issues...$(RESET)"
	@swiftlint lint --fix --quiet
	@echo "$(GREEN)$(CHECK) Lint fixes applied$(RESET)"

format: ## Format code with swift-format
	@echo "$(BOLD)$(LINT_ICON) Formatting code...$(RESET)"
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format format -i -r Jools $(JOOLSKIT_PATH)/Sources $(JOOLSKIT_PATH)/Tests JoolsTests; \
		echo "$(GREEN)$(CHECK) Code formatted$(RESET)"; \
	else \
		echo "$(YELLOW)$(ARROW) swift-format not installed, skipping$(RESET)"; \
	fi

# ─────────────────────────────────────────────────────────────────────────────────
# Clean
# ─────────────────────────────────────────────────────────────────────────────────

clean: ## Clean build artifacts
	@echo "$(BOLD)$(BROOM) Cleaning build artifacts...$(RESET)"
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null || true
	@rm -rf $(BUILD_DIR)
	@echo "$(GREEN)$(CHECK) Clean complete$(RESET)"

clean-all: clean kit-clean ## Clean everything including DerivedData
	@echo "$(BOLD)$(BROOM) Deep cleaning...$(RESET)"
	@rm -rf ~/Library/Developer/Xcode/DerivedData/$(PRODUCT_NAME)-*
	@rm -rf .swiftpm
	@echo "$(GREEN)$(CHECK) Deep clean complete$(RESET)"

# ─────────────────────────────────────────────────────────────────────────────────
# JoolsKit (Swift Package)
# ─────────────────────────────────────────────────────────────────────────────────

kit-build: ## Build JoolsKit package
	@echo "$(BOLD)$(PACKAGE) Building JoolsKit...$(RESET)"
	@cd $(JOOLSKIT_PATH) && swift build
	@echo "$(GREEN)$(CHECK) JoolsKit built$(RESET)"

kit-test: ## Run JoolsKit tests
	@echo "$(BOLD)$(TEST_ICON) Testing JoolsKit...$(RESET)"
	@cd $(JOOLSKIT_PATH) && swift test
	@echo "$(GREEN)$(CHECK) JoolsKit tests passed$(RESET)"

kit-clean: ## Clean JoolsKit build
	@echo "$(BOLD)$(BROOM) Cleaning JoolsKit...$(RESET)"
	@cd $(JOOLSKIT_PATH) && swift package clean
	@echo "$(GREEN)$(CHECK) JoolsKit cleaned$(RESET)"

kit-update: ## Update JoolsKit dependencies
	@echo "$(BOLD)$(PACKAGE) Updating JoolsKit dependencies...$(RESET)"
	@cd $(JOOLSKIT_PATH) && swift package update
	@echo "$(GREEN)$(CHECK) Dependencies updated$(RESET)"

# ─────────────────────────────────────────────────────────────────────────────────
# CI/CD
# ─────────────────────────────────────────────────────────────────────────────────

ci: lint kit-build kit-test build test-app ## Run full CI pipeline (lint → build → test)
	@echo ""
	@echo "$(BG_GREEN)$(BOLD)$(WHITE)                                                                 $(RESET)"
	@echo "$(BG_GREEN)$(BOLD)$(WHITE)   $(CHECK) CI PIPELINE PASSED                                       $(RESET)"
	@echo "$(BG_GREEN)$(BOLD)$(WHITE)                                                                 $(RESET)"
	@echo ""

pre-push: ci ## Pre-push hook target (runs full CI)
	@echo "$(GREEN)$(CHECK) Pre-push checks passed$(RESET)"

# ─────────────────────────────────────────────────────────────────────────────────
# Release
#
# `make release VERSION=1.2.3` prepares everything that has to be in
# place BEFORE you tag a release:
#
#   1. Bump MARKETING_VERSION in project.yml
#   2. Re-run xcodegen so the bump lands in Jools.xcodeproj
#   3. Rename `## [Unreleased]` in CHANGELOG.md to `## [VERSION] — DATE`
#      and add a fresh empty `## [Unreleased]` section above it
#   4. Print the exact `git commit` / `git tag` / `git push` commands
#      for you to run by hand
#
# This target deliberately does NOT auto-commit, auto-tag, or auto-push.
# Tagging is destructive (you can't gracefully un-publish a tag from
# GitHub once the release workflow runs against it), so the actual
# hand-off step is yours.
#
# After you push the tag, `.github/workflows/release.yml` builds a
# Release-configuration .app for the simulator, packages it as a zip,
# and creates a GitHub Release with the matching CHANGELOG entry as
# the body.
#
# Example:
#   make release VERSION=1.0.1
#   git diff                                  # eyeball the bump
#   git add project.yml CHANGELOG.md
#   git commit -m "chore(release): v1.0.1"
#   git tag -a v1.0.1 -m "v1.0.1"
#   git push origin main
#   git push origin v1.0.1                   # this fires release.yml
# ─────────────────────────────────────────────────────────────────────────────────

release: ## Prepare a release: bump version + update CHANGELOG (use VERSION=x.y.z)
ifndef VERSION
	@echo "$(RED)$(CROSS) VERSION not set. Usage: make release VERSION=1.2.3$(RESET)" >&2
	@exit 1
endif
	@# Validate semver shape: MAJOR.MINOR.PATCH with optional -prerelease.
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$$' || \
		(echo "$(RED)$(CROSS) VERSION '$(VERSION)' is not valid semver (expected MAJOR.MINOR.PATCH[-prerelease]).$(RESET)" >&2 && exit 1)
	@echo "$(BOLD)$(ROCKET) Preparing release v$(VERSION)$(RESET)"
	@# Step 1: bump MARKETING_VERSION in project.yml.
	@CURRENT=$$(awk '/MARKETING_VERSION:/ {gsub(/"/, "", $$2); print $$2; exit}' project.yml); \
	if [ "$$CURRENT" = "$(VERSION)" ]; then \
		echo "$(YELLOW)$(ARROW) project.yml MARKETING_VERSION is already $(VERSION) — leaving untouched$(RESET)"; \
	else \
		echo "$(CYAN)$(ARROW) project.yml: $$CURRENT → $(VERSION)$(RESET)"; \
		/usr/bin/sed -i.bak -E 's/^([[:space:]]*MARKETING_VERSION:[[:space:]]*)\".*\"/\1"$(VERSION)"/' project.yml && rm project.yml.bak; \
	fi
	@# Step 2: regenerate the Xcode project so the bump propagates.
	@$(MAKE) --no-print-directory generate >/dev/null
	@# Step 3: roll the CHANGELOG. Insert "## [VERSION] — DATE" right
	@# below the existing "## [Unreleased]" header, then re-add a fresh
	@# empty Unreleased section above it. Idempotent: if the version
	@# section already exists, leave the CHANGELOG alone.
	@if grep -Eq '^## \[$(VERSION)\]' CHANGELOG.md; then \
		echo "$(YELLOW)$(ARROW) CHANGELOG.md already has a [$(VERSION)] section — leaving untouched$(RESET)"; \
	else \
		echo "$(CYAN)$(ARROW) CHANGELOG.md: rolling [Unreleased] → [$(VERSION)] — $$(date -u +%Y-%m-%d)$(RESET)"; \
		TODAY=$$(date -u +%Y-%m-%d); \
		/usr/bin/awk -v ver="$(VERSION)" -v today="$$TODAY" '\
			/^## \[Unreleased\]/ && !done { \
				print; \
				print ""; \
				print "## [" ver "] — " today; \
				done = 1; next \
			} { print }' CHANGELOG.md > CHANGELOG.md.new && mv CHANGELOG.md.new CHANGELOG.md; \
	fi
	@# Step 4: walk the user through the publish steps. Print absolute
	@# git commands they can copy-paste — no auto-execute.
	@echo ""
	@echo "$(BOLD)$(GREEN)Release prep complete.$(RESET)"
	@echo ""
	@echo "$(BOLD)Next steps (run by hand):$(RESET)"
	@echo "  $(CYAN)1.$(RESET) Review the changes:"
	@echo "       $(WHITE)git diff project.yml CHANGELOG.md$(RESET)"
	@echo "  $(CYAN)2.$(RESET) Fill in the [$(VERSION)] CHANGELOG entry with anything"
	@echo "     not already captured under [Unreleased]."
	@echo "  $(CYAN)3.$(RESET) Commit and tag:"
	@echo "       $(WHITE)git add project.yml CHANGELOG.md$(RESET)"
	@echo "       $(WHITE)git commit -m \"chore(release): v$(VERSION)\"$(RESET)"
	@echo "       $(WHITE)git tag -a v$(VERSION) -m \"v$(VERSION)\"$(RESET)"
	@echo "  $(CYAN)4.$(RESET) Push (the tag push triggers .github/workflows/release.yml):"
	@echo "       $(WHITE)git push origin HEAD$(RESET)"
	@echo "       $(WHITE)git push origin v$(VERSION)$(RESET)"
	@echo ""

# ─────────────────────────────────────────────────────────────────────────────────
# CI: build-for-testing + split test execution
#
# The GitHub Actions iOS pipeline is split into three jobs:
#   1. ci-build-for-testing   — compiles app + tests once, packages output
#   2. ci-test-unit           — downloads package, runs JoolsTests only
#   3. ci-test-ui             — downloads package, runs JoolsUITests only
#
# Jobs 2 and 3 run in parallel so wall time is max(unit, ui), not unit+ui.
# Locally these targets use the same .ci-build/ DerivedData dir so warm
# rebuilds are ~instant.
#
# Simulator handling — no hardcoded device names:
#
# The build compiles against `generic/platform=iOS Simulator`, which
# is a scheme-agnostic "any iOS sim" destination that xcodebuild
# accepts without prior scheme build metadata. No specific device is
# chosen at build time.
#
# Each test job discovers its own concrete iPhone simulator UDID at
# runtime via `scripts/ci-discover-sim`, which parses `xcrun simctl
# list devices available -j` and returns the first iPhone in the
# latest iOS runtime installed on the runner. This adapts
# automatically as GitHub's macos-15 image churns its simulator
# lineup — nothing needs to be updated in this repo.
# ─────────────────────────────────────────────────────────────────────────────────

CI_DERIVED_DATA      := .ci-build
CI_ARTIFACT          := build-products.tar
CI_SIM_DISCOVERY     := scripts/ci-discover-sim

# Destination resolution for test targets (precedence high → low):
#   1. $(SIM_UDID)             explicit UDID override (local dev pinning)
#   2. $(SIM_NAME)             explicit name override
#   3. ci-discover-sim         auto-pick latest-iOS iPhone via simctl
# The build target uses `generic/platform=iOS Simulator` unconditionally
# because it doesn't need — and historically cannot reliably get — a
# concrete device before any build has happened on a fresh runner.

CI_BUILD_DESTINATION := generic/platform=iOS Simulator
# Runner architecture — constrains the build-for-testing output so we
# don't ship a fat arm64+x86_64 tarball. `uname -m` is the right source
# of truth: macos-15 GitHub runners return `arm64`, dev machines too.
CI_BUILD_ARCHS       := $(shell uname -m)

ci-build-for-testing: ## CI: build-for-testing into .ci-build/
	@echo "$(BOLD)$(BUILD_ICON) [CI] build-for-testing → $(CI_DERIVED_DATA)$(RESET)"
	@echo "$(CYAN)$(ARROW) destination: $(CI_BUILD_DESTINATION) (ARCHS=$(CI_BUILD_ARCHS))$(RESET)"
	@# ARCHS/EXCLUDED_ARCHS constrain the fat-binary build to the
	@# runner arch only. Without this, `generic/platform=iOS
	@# Simulator` compiles BOTH arm64 and x86_64, which roughly
	@# doubles the build time and bloats the xctestrun tarball from
	@# ~200 MB to ~375 MB. macos-15 GitHub runners (and all modern
	@# Apple Silicon dev machines) are arm64-only, so x86_64 is
	@# dead weight on both sides.
	@set -o pipefail && xcodebuild build-for-testing \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "$(CI_BUILD_DESTINATION)" \
		-configuration Debug \
		-derivedDataPath $(CI_DERIVED_DATA) \
		ARCHS=$(CI_BUILD_ARCHS) \
		EXCLUDED_ARCHS= \
		ONLY_ACTIVE_ARCH=NO \
		-quiet
	@echo "$(GREEN)$(CHECK) [CI] build-for-testing complete$(RESET)"

ci-package-build: ## CI: tar .ci-build/Build for the artifact handoff
	@echo "$(BOLD)$(PACKAGE) [CI] packaging $(CI_ARTIFACT)$(RESET)"
	@test -d $(CI_DERIVED_DATA)/Build || (echo "$(RED)$(CROSS) $(CI_DERIVED_DATA)/Build not found — run ci-build-for-testing first$(RESET)" && exit 1)
	@tar -cf $(CI_ARTIFACT) -C $(CI_DERIVED_DATA) Build
	@ls -lh $(CI_ARTIFACT)

ci-unpack-build: ## CI: untar build-products.tar into .ci-build/
	@echo "$(BOLD)$(PACKAGE) [CI] unpacking $(CI_ARTIFACT) → $(CI_DERIVED_DATA)$(RESET)"
	@test -f $(CI_ARTIFACT) || (echo "$(RED)$(CROSS) $(CI_ARTIFACT) not found$(RESET)" && exit 1)
	@mkdir -p $(CI_DERIVED_DATA)
	@tar -xf $(CI_ARTIFACT) -C $(CI_DERIVED_DATA)
	@echo "$(GREEN)$(CHECK) [CI] build products unpacked$(RESET)"

# Shared test-without-building recipe. Resolves the xctestrun produced
# by ci-build-for-testing, picks a concrete simulator (explicit env
# override → auto-discovered iPhone), and runs the supplied target.
# $(1) = `-only-testing` value (e.g. JoolsTests or JoolsUITests).
define CI_RUN_TEST
	@XCTESTRUN=$$(ls $(CI_DERIVED_DATA)/Build/Products/*.xctestrun 2>/dev/null | head -1); \
	if [ -z "$$XCTESTRUN" ]; then \
	    echo "$(RED)$(CROSS) No .xctestrun found in $(CI_DERIVED_DATA)/Build/Products — run ci-build-for-testing first$(RESET)" >&2; \
	    exit 1; \
	fi; \
	if [ -n "$(SIM_UDID)" ]; then \
	    DEST="platform=iOS Simulator,id=$(SIM_UDID)"; \
	elif [ -n "$(SIM_NAME)" ]; then \
	    DEST="platform=iOS Simulator,name=$(SIM_NAME)"; \
	else \
	    UDID=$$($(CI_SIM_DISCOVERY)) || exit 1; \
	    DEST="platform=iOS Simulator,id=$$UDID"; \
	fi; \
	echo "$(CYAN)$(ARROW) xctestrun: $$XCTESTRUN$(RESET)"; \
	echo "$(CYAN)$(ARROW) destination: $$DEST$(RESET)"; \
	set -o pipefail && xcodebuild test-without-building \
		-xctestrun "$$XCTESTRUN" \
		-destination "$$DEST" \
		-only-testing:$(1) \
		-quiet
endef

ci-test-unit: ## CI: test-without-building for JoolsTests only
	@echo "$(BOLD)$(TEST_ICON) [CI] test-without-building → JoolsTests$(RESET)"
	$(call CI_RUN_TEST,JoolsTests)
	@echo "$(GREEN)$(CHECK) [CI] JoolsTests passed$(RESET)"

ci-test-ui: ## CI: test-without-building for JoolsUITests only
	@echo "$(BOLD)$(TEST_ICON) [CI] test-without-building → JoolsUITests$(RESET)"
	$(call CI_RUN_TEST,JoolsUITests)
	@echo "$(GREEN)$(CHECK) [CI] JoolsUITests passed$(RESET)"

ci-test: ## CI: test-without-building for ALL targets in one invocation (shared sim boot)
	@echo "$(BOLD)$(TEST_ICON) [CI] test-without-building → all targets$(RESET)"
	@XCTESTRUN=$$(ls $(CI_DERIVED_DATA)/Build/Products/*.xctestrun 2>/dev/null | head -1); \
	if [ -z "$$XCTESTRUN" ]; then \
	    echo "$(RED)$(CROSS) No .xctestrun found in $(CI_DERIVED_DATA)/Build/Products — run ci-build-for-testing first$(RESET)" >&2; \
	    exit 1; \
	fi; \
	if [ -n "$(SIM_UDID)" ]; then \
	    DEST="platform=iOS Simulator,id=$(SIM_UDID)"; \
	elif [ -n "$(SIM_NAME)" ]; then \
	    DEST="platform=iOS Simulator,name=$(SIM_NAME)"; \
	else \
	    UDID=$$($(CI_SIM_DISCOVERY)) || exit 1; \
	    DEST="platform=iOS Simulator,id=$$UDID"; \
	fi; \
	echo "$(CYAN)$(ARROW) xctestrun: $$XCTESTRUN$(RESET)"; \
	echo "$(CYAN)$(ARROW) destination: $$DEST$(RESET)"; \
	set -o pipefail && xcodebuild test-without-building \
		-xctestrun "$$XCTESTRUN" \
		-destination "$$DEST" \
		-quiet
	@echo "$(GREEN)$(CHECK) [CI] all tests passed$(RESET)"

# ─────────────────────────────────────────────────────────────────────────────────
# Git Helpers
# ─────────────────────────────────────────────────────────────────────────────────

status: ## Show git status
	@git status -sb

diff: ## Show git diff
	@git diff --stat

log: ## Show recent commits
	@git log --oneline -10

# ─────────────────────────────────────────────────────────────────────────────────
# Simulator
# ─────────────────────────────────────────────────────────────────────────────────

# Simulator configuration
BUNDLE_ID := com.indrasvat.jataayu
BUILD_OUTPUT := build/Build/Products/Debug-iphonesimulator/$(PRODUCT_NAME).app

sim-list: ## List available iOS simulators
	@echo "$(BOLD)📱 Available iOS Simulators:$(RESET)"
	@echo ""
	@xcrun simctl list devices available | grep -E "(-- iOS|iPhone|iPad)" | head -30
	@echo ""
	@SIM_UUID=$$(xcrun simctl list devices available | grep "iPhone 17 Pro" | head -1 | grep -oE '[A-F0-9-]{36}'); \
	if [ -z "$$SIM_UUID" ]; then \
		SIM_UUID=$$(xcrun simctl list devices available | grep "iPhone" | head -1 | grep -oE '[A-F0-9-]{36}'); \
	fi; \
	if [ -n "$$SIM_UUID" ]; then \
		SIM_NAME=$$(xcrun simctl list devices available | grep "$$SIM_UUID" | sed 's/ *(.*//' | xargs); \
		echo "$(GREEN)$(CHECK) Selected: $$SIM_NAME ($$SIM_UUID)$(RESET)"; \
	else \
		echo "$(RED)$(CROSS) No suitable simulator found$(RESET)"; \
		echo ""; \
		echo "$(YELLOW)Install iOS simulator with:$(RESET)"; \
		echo "  $(CYAN)xcodebuild -downloadPlatform iOS$(RESET)"; \
		echo ""; \
		echo "$(YELLOW)Or create one manually:$(RESET)"; \
		echo "  $(CYAN)xcrun simctl create \"iPhone 17 Pro\" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-0$(RESET)"; \
	fi

sim-boot: ## Boot the iOS simulator
	@SIM_UUID=$$(xcrun simctl list devices available | grep "iPhone 17 Pro" | head -1 | grep -oE '[A-F0-9-]{36}'); \
	if [ -z "$$SIM_UUID" ]; then \
		SIM_UUID=$$(xcrun simctl list devices available | grep "iPhone" | head -1 | grep -oE '[A-F0-9-]{36}'); \
	fi; \
	if [ -z "$$SIM_UUID" ]; then \
		echo "$(RED)$(CROSS) No suitable simulator found$(RESET)"; \
		echo "$(YELLOW)Run 'make sim-list' for help$(RESET)"; \
		exit 1; \
	fi; \
	SIM_NAME=$$(xcrun simctl list devices available | grep "$$SIM_UUID" | sed 's/ *(.*//' | xargs); \
	echo "$(BOLD)📱 Booting $$SIM_NAME...$(RESET)"; \
	xcrun simctl boot "$$SIM_UUID" 2>/dev/null || true; \
	open -a Simulator; \
	echo "$(GREEN)$(CHECK) Simulator running$(RESET)"

sim-install: ## Install app on booted simulator
	@if [ ! -d "$(BUILD_OUTPUT)" ]; then \
		echo "$(RED)$(CROSS) App not built. Run 'make sim-build' first$(RESET)"; \
		exit 1; \
	fi
	@echo "$(BOLD)📲 Installing $(PRODUCT_NAME)...$(RESET)"
	@xcrun simctl install booted "$(BUILD_OUTPUT)"
	@echo "$(GREEN)$(CHECK) App installed$(RESET)"

sim-build: ## Build app for simulator with local build dir
	@SIM_UUID=$$(xcrun simctl list devices available | grep "iPhone 17 Pro" | head -1 | grep -oE '[A-F0-9-]{36}'); \
	if [ -z "$$SIM_UUID" ]; then \
		SIM_UUID=$$(xcrun simctl list devices available | grep "iPhone" | head -1 | grep -oE '[A-F0-9-]{36}'); \
	fi; \
	if [ -z "$$SIM_UUID" ]; then \
		echo "$(RED)$(CROSS) No suitable simulator found$(RESET)"; \
		echo "$(YELLOW)Run 'make sim-list' for help$(RESET)"; \
		exit 1; \
	fi; \
	SIM_NAME=$$(xcrun simctl list devices available | grep "$$SIM_UUID" | sed 's/ *(.*//' | xargs); \
	echo "$(BOLD)$(BUILD_ICON) Building $(PRODUCT_NAME) for $$SIM_NAME...$(RESET)"; \
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "platform=iOS Simulator,id=$$SIM_UUID" \
		-derivedDataPath build \
		-configuration Debug \
		build 2>&1 | grep -E "(error:|warning:|BUILD)" || true; \
	if [ -d "$(BUILD_OUTPUT)" ]; then \
		echo "$(GREEN)$(CHECK) Build succeeded$(RESET)"; \
	else \
		echo "$(RED)$(CROSS) Build failed$(RESET)"; \
		exit 1; \
	fi

sim-run: sim-build sim-boot sim-install ## Build, install and run app on simulator
	@echo "$(BOLD)$(ROCKET) Launching $(PRODUCT_NAME)...$(RESET)"
	@xcrun simctl launch booted "$(BUNDLE_ID)"
	@echo "$(GREEN)$(CHECK) App running$(RESET)"

sim-launch: ## Launch already-installed app on simulator
	@echo "$(BOLD)$(ROCKET) Launching $(PRODUCT_NAME)...$(RESET)"
	@xcrun simctl launch booted "$(BUNDLE_ID)" || (echo "$(RED)$(CROSS) App not installed. Run 'make sim-run' first$(RESET)" && exit 1)
	@echo "$(GREEN)$(CHECK) App launched$(RESET)"

sim-kill: ## Terminate app on simulator
	@echo "$(BOLD)Terminating $(PRODUCT_NAME)...$(RESET)"
	@xcrun simctl terminate booted "$(BUNDLE_ID)" 2>/dev/null || true
	@echo "$(GREEN)$(CHECK) App terminated$(RESET)"

sim-logs: ## Stream app logs from simulator
	@echo "$(BOLD)📋 Streaming logs for $(PRODUCT_NAME)...$(RESET)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(RESET)"
	@xcrun simctl spawn booted log stream --predicate 'subsystem == "$(BUNDLE_ID)"' --level debug

sim-shutdown: ## Shutdown all simulators
	@echo "$(BOLD)Shutting down simulators...$(RESET)"
	@xcrun simctl shutdown all
	@echo "$(GREEN)$(CHECK) All simulators shut down$(RESET)"

sim-reload: sim-kill sim-install sim-launch ## Quick reload (kill + install + launch, no rebuild)

sim-screenshot: ## Take simulator screenshot (override path: SCREENSHOT=/path/to/file.png)
	@echo "$(BOLD)📸 Taking screenshot...$(RESET)"
	@xcrun simctl io booted screenshot "$(SCREENSHOT)"
	@echo "$(GREEN)$(CHECK) Screenshot saved to $(SCREENSHOT)$(RESET)"

sim-ui-smoke: ## Capture current simulator UI using AXe
ifndef AXE
	$(error "$(RED)$(CROSS) axe not found. Install with 'brew install axe'$(RESET)")
endif
	@echo "$(BOLD)$(TEST_ICON) Describing simulator UI with AXe...$(RESET)"
	@axe describe-ui

sim-screenshot-bundle: ## Capture a timestamped screenshot bundle into SCREENSHOT_DIR
	@mkdir -p "$(SCREENSHOT_DIR)"
	@STAMP=$$(date +%Y%m%d-%H%M%S); \
	OUT="$(SCREENSHOT_DIR)/jataayu-$$STAMP.png"; \
	echo "$(BOLD)📸 Saving screenshot to $$OUT$(RESET)"; \
	xcrun simctl io booted screenshot "$$OUT" >/dev/null; \
	echo "$(GREEN)$(CHECK) Screenshot saved to $$OUT$(RESET)"

verify-live-session: ## Print the manual live-session verification checklist
	@echo "$(BOLD)$(TEST_ICON) Live Jules verification checklist$(RESET)"
	@echo "  1. Open the hews session in Jools and in jules.google.com."
	@echo "  2. Send a follow-up from Jools and confirm the optimistic bubble appears immediately."
	@echo "  3. Confirm the session header changes to Running and the prior timeline remains visible."
	@echo "  4. Confirm the banner shows the current step title and description."
	@echo "  5. Background and foreground the app; verify the session catches up without relaunch."
	@echo "  6. Capture screenshots before send, while running, and after the final answer arrives."
