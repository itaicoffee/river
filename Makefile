.PHONY: build test install uninstall run

build:
	swift build -c release

test:
	swift test

run:
	swift run river run

install: build
	.build/release/river install

uninstall:
	@if [ -x "$$HOME/.local/bin/river" ]; then \
		"$$HOME/.local/bin/river" uninstall; \
	else \
		swift run river uninstall; \
	fi
