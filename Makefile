.DEFAULT_GOAL := help
.PHONY: help build run release test clean

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  help     Show this help message (default)"
	@echo "  build    Build and assemble debug GotifyDesktop.app"
	@echo "  run      Build and launch debug GotifyDesktop.app"
	@echo "  test     Run unit tests"
	@echo "  release  Package arm64 and amd64 release .dmg installers in .build/dist/"
	@echo "  clean    Remove build artifacts (.build)"

build:
	@./Tools/build-app.sh

run:
	@app_path="$$(./Tools/build-app.sh)" && open "$$app_path"

release:
	@./Tools/build-app.sh --release

test:
	swift test

clean:
	swift package clean
	rm -rf .build
