# odin-glycin: Odin bindings for glycin 2 and libglycin-gtk4. Consumed via -collection:glycin=/path/to/odin-glycin
# What every runic binding does is in house/binding.mk, a copy of house-rules'
# scripts/binding/binding.mk: this repository is public, and its runner has no house-rules.
# project.toml names the kind, the packages, the siblings and the system packages.
include house/binding.mk

# The glycin the binding is generated from and tested against is the suite's, amber-glycin
# (glycin 2.2.1, from amber-glycin-dev), the only libglycin there is (Mint 22 has none), in its
# own folder off the linker's path, with amber-gtk4 for GTK: a test links both from there, runs
# them through the run path and points GLYCIN_DATA_DIR at the package's loader configs, as every
# program built on the binding does. The loaders run in glycin's sandbox. The tests run under
# Xvfb, as glycin_gtk4's open GTK; generate reads the bundles' headers.
GLYCIN_LIB = /usr/lib/amber-glycin
GTK_LIB = /usr/lib/amber-gtk4
GLYCIN_LINK = -extra-linker-flags:"-L$(GLYCIN_LIB) -L$(GTK_LIB) -Wl,-rpath,$(GLYCIN_LIB):$(GTK_LIB)"
# The headers carry no version macro: the package's .pc file does, and the tests read it from
# here. glycin and glycin-gtk4 are one release, so their .pc files carry the same version.
GLYCIN_VERSION = $(shell sed -n 's/^Version: //p' $(GLYCIN_LIB)/pkgconfig/glycin-2.pc 2>/dev/null)
ODIN_TEST_FLAGS += $(GLYCIN_LINK) -define:GLYCIN_VERSION=$(GLYCIN_VERSION)
test test-big: export GLYCIN_DATA_DIR = $(GLYCIN_LIB)/share
test test-big: export GLYCIN_LIB := $(GLYCIN_LIB)
test: ODIN = xvfb-run -a odin
generate: export GLYCIN_INCLUDE = $(GLYCIN_LIB)/include
generate: export GTK_INCLUDE = $(GTK_LIB)/include

EXAMPLES = view info

.PHONY: check-stage examples test-big
check-stage:
	@test -f $(GLYCIN_LIB)/libglycin-2.so || { echo "glycin 2.2.1 not found in $(GLYCIN_LIB): install amber-glycin-dev (make init-packages)"; exit 2; }
	@test -f $(GTK_LIB)/libgtk-4.so || { echo "GTK 4.16.13 not found in $(GTK_LIB): install amber-gtk4-dev (make init-packages)"; exit 2; }

check: check-stage examples
test: check-stage

examples: check-stage ## build the example programs
	@mkdir -p build
	@for e in $(EXAMPLES); do echo "== build examples/$$e =="; $(ODIN) build examples/$$e $(ODIN_FLAGS) $(GLYCIN_LINK) -out:build/$$e || exit 1; done

# Decodes an 8.6 GB frame, which glycin must refuse: needs about 17 GB free and 40 s, so it is not in ci.
test-big: check-stage ## decode an image over glycin's 8 GB frame limit (needs ~17 GB free RAM)
	@mkdir -p build
	@scripts/big-fixture.sh build/big.png
	env -u DISPLAY -u WAYLAND_DISPLAY GLYCIN_TEST_BIG=$(abspath build/big.png) $(ODIN) test glycin $(ODIN_TEST_FLAGS) -define:ODIN_TEST_NAMES=glycin.test_oversized_image_is_refused -out:build/glycin_big_test
