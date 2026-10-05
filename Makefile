.PHONY: help build test app install signing eval references clean

help:
	@echo "make test        run MurmurCore unit tests"
	@echo "make build       build the app and eval CLI (release)"
	@echo "make signing     choose a stable code-signing identity (once)"
	@echo "make app         build and sign build/Murmur.app"
	@echo "make install     install /Applications/Murmur.app (then launch it from Spotlight)"
	@echo "make eval        score speech recognition on evals/manifest.json"
	@echo "make references  clone the reference repos into ./references"

build:
	swift build -c release --product Murmur
	swift build -c release --product murmur-eval

test:
	swift test --package-path Packages/MurmurCore

app:
	scripts/build-app.sh

install:
	scripts/install.sh

signing:
	scripts/setup-signing.sh

eval:
	swift run -c release murmur-eval run

references:
	scripts/fetch-references.sh

clean:
	rm -rf .build build Packages/MurmurCore/.build
