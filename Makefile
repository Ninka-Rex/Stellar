# Stellar – top-level convenience Makefile
# Delegates to CMake presets; does NOT replace CMake.

UNAME := $(shell uname -s 2>/dev/null || echo Windows)

ifeq ($(findstring MINGW,$(UNAME)),MINGW)
  PRESET_PREFIX := windows
else ifeq ($(findstring MSYS,$(UNAME)),MSYS)
  PRESET_PREFIX := windows
else ifeq ($(UNAME),Windows)
  PRESET_PREFIX := windows
else
  PRESET_PREFIX := linux
endif

.PHONY: all debug release configure-debug configure-release clean run help

all: debug

configure-debug:
	cmake --preset $(PRESET_PREFIX)-debug

configure-release:
	cmake --preset $(PRESET_PREFIX)-release

debug: configure-debug
	cmake --build --preset $(PRESET_PREFIX)-debug

release: configure-release
	cmake --build --preset $(PRESET_PREFIX)-release

run: debug
	./build/$(PRESET_PREFIX)-debug/Stellar

clean:
	rm -rf build/

# Extension helpers
.PHONY: ext-pack-chrome ext-pack-firefox
ext-pack-chrome:
	cd extensions/chrome && zip -r ../../build/stellar-chrome.zip . -x "*.DS_Store"

ext-pack-firefox:
	cd extensions/firefox && zip -r ../../build/stellar-firefox.zip . -x "*.DS_Store"

help:
	@echo "Targets:"
	@echo "  debug           Build debug configuration (default)"
	@echo "  release         Build release configuration"
	@echo "  run             Build debug then launch"
	@echo "  clean           Remove all build artifacts"
	@echo "  ext-pack-chrome Pack Chrome extension zip"
	@echo "  ext-pack-firefox Pack Firefox extension zip"
