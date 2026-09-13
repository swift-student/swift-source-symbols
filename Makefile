SWIFT ?= swift
SWIFTLINT_VERSION = 0.65.1
SWIFTFORMAT_VERSION = 0.62.1

.PHONY: build test tools lint format format-check check example
build:
	$(SWIFT) build
test:
	$(SWIFT) test
tools:
	@test "$$(swiftlint version)" = "$(SWIFTLINT_VERSION)" || (echo "Install SwiftLint $(SWIFTLINT_VERSION)"; exit 1)
	@test "$$(swiftformat --version)" = "$(SWIFTFORMAT_VERSION)" || (echo "Install SwiftFormat $(SWIFTFORMAT_VERSION)"; exit 1)
lint: tools
	swiftlint lint --strict
format: tools
	swiftformat .
format-check: tools
	swiftformat . --lint
example:
	$(SWIFT) run UsageExample
check: build test lint format-check example
