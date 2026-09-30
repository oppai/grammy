.PHONY: build app run clean

build:
	swift build

app:
	./scripts/build-app.sh

run: app
	open build/Grammy.app

clean:
	rm -rf .build build
