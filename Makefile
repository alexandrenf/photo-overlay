SWIFT ?= swift

.PHONY: build run test app zip clean

build:
	$(SWIFT) build

run:
	$(SWIFT) run Overlay

test:
	$(SWIFT) test

app:
	./scripts/package_app.sh

zip:
	./scripts/package_app.sh --zip

clean:
	$(SWIFT) package clean
	@echo "Swift build artifacts removed. Packaged apps remain in dist/."
