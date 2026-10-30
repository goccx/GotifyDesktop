.PHONY: all build run release test clean

all: build

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
