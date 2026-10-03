# odin-glycin: Odin bindings for glycin 2 and libglycin-gtk4. Consumed via -collection:glycin=/path/to/odin-glycin
# Each entry is a package directory at the repo root; one with no .odin file yet is skipped.
PACKAGES = $(foreach p,glycin glycin_gtk4,$(if $(wildcard $(p)/*.odin),$(p)))
# runic is the suite's fork (branch amber-patched, runic/amber-build.sh), pinned in odin-glib/docs/DECISIONS.md §2.
RUNIC ?= ../runic/build/runic
BRANCH ?= main
REMOTE ?= origin
ROOT_COMMIT_MSG ?= Initial odin-glycin
GLIB ?= ../odin-glib
CAIRO ?= ../odin-cairo
PANGO ?= ../odin-pango
GRAPHENE ?= ../odin-graphene
PIXBUF ?= ../odin-gdk-pixbuf
GTK4 ?= ../odin-gtk4
# amber-glycin's build is the only libglycin there is (Mint 22 has none): the tests link and
# load it, and the loaders it staged run in glycin's sandbox. GLYCIN_DATA_DIR points at a copy of
# the loader configs with Exec= rewritten to the stage (scripts/data-dir.sh).
GLYCIN_STAGE ?= ../amber-glycin/build/glycin/stage
GTK_STAGE ?= ../amber-gtk4/build/gtk/stage
GLYCIN_LIB = $(abspath $(GLYCIN_STAGE)/usr/lib/amber-glycin)
GTK_LIB = $(abspath $(GTK_STAGE)/usr/lib/amber-gtk4)
# The headers carry no version macro: the staged .pc files do, and the tests read them from here.
GLYCIN_VERSION = $(shell sed -n 's/^Version: //p' $(GLYCIN_LIB)/pkgconfig/glycin-2.pc 2>/dev/null)
GLYCIN_GTK4_VERSION = $(shell sed -n 's/^Version: //p' $(GLYCIN_LIB)/pkgconfig/glycin-gtk4-2.pc 2>/dev/null)
LINK_FLAGS = -extra-linker-flags:"-L$(GLYCIN_LIB) -L$(GTK_LIB) -Wl,-rpath,$(GLYCIN_LIB) -Wl,-rpath,$(GTK_LIB)"
DATA_DIR = $(abspath build/glycin-data)
TEST_ENV = LD_LIBRARY_PATH=$(GLYCIN_LIB):$(GTK_LIB) GLYCIN_DATA_DIR=$(DATA_DIR) GLYCIN_LIB=$(GLYCIN_LIB)
# A test that leaks or frees badly fails, rather than only warning. `make test ASAN=1` runs
# the tests under AddressSanitizer as well.
ASAN ?=
# -vet matters beyond this repo: odin test compiles the #+test files of every imported package
# with the consumer's flags, so a vet error here breaks every program that tests against it.
TEST_FLAGS = -vet -strict-style -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true $(LINK_FLAGS) $(if $(ASAN),-debug -sanitize:address)
# Every collection the packages import; sibling paths are `?=` variables above.
COLLECTIONS ?= -collection:glycin=. -collection:glib=$(GLIB) -collection:cairo=$(CAIRO) -collection:pango=$(PANGO) -collection:graphene=$(GRAPHENE) -collection:pixbuf=$(PIXBUF) -collection:gtk4=$(GTK4)
EXAMPLES = view info

.PHONY: help deps generate check test ci clean push force-push lint api check-api check-generated check-no-agent-files check-test-tag test-big check-stage check-cheatsheet-compile

check-stage:
	@test -f $(GLYCIN_LIB)/libglycin-2.so.0 || { echo "amber-glycin is not built: $(GLYCIN_LIB) has no libglycin-2 (run 'make glycin' in ../amber-glycin)"; exit 2; }
	@test -f $(GTK_LIB)/libgtk-4.so.1 || { echo "amber-gtk4 is not built: $(GTK_LIB) has no libgtk-4 (run its make gtk)"; exit 2; }

check: check-test-tag check-stage ## type-check every package with -vet -strict-style, build the examples
	@for p in $(PACKAGES); do echo "== check $$p =="; odin check $$p $(COLLECTIONS) -no-entry-point -vet -strict-style || exit 1; done
	@mkdir -p build
	@for e in $(EXAMPLES); do echo "== build examples/$$e =="; odin build examples/$$e $(COLLECTIONS) $(LINK_FLAGS) -vet -strict-style -out:build/$$e || exit 1; done

test: check-stage ## run every package's tests (ASAN=1 adds AddressSanitizer)
	@mkdir -p build
	@scripts/data-dir.sh $(GLYCIN_LIB) /usr/lib/amber-glycin $(DATA_DIR)
	@for p in $(PACKAGES); do echo "== test $$p =="; \
		if [ $$p = glycin_gtk4 ]; then run="xvfb-run -a env -u WAYLAND_DISPLAY"; ver=$(GLYCIN_GTK4_VERSION); else run="env -u DISPLAY -u WAYLAND_DISPLAY"; ver=$(GLYCIN_VERSION); fi; \
		$$run $(TEST_ENV) odin test $$p $(COLLECTIONS) $(TEST_FLAGS) -define:GLYCIN_VERSION=$$ver -out:build/$${p}_test || exit 1; done

# Decodes an 8.6 GB frame, which glycin must refuse: needs about 17 GB free and 40 s, so it is not in ci.
test-big: check-stage ## decode an image over glycin's 8 GB frame limit (needs ~17 GB free RAM)
	@mkdir -p build
	@scripts/data-dir.sh $(GLYCIN_LIB) /usr/lib/amber-glycin $(DATA_DIR)
	@scripts/big-fixture.sh build/big.png
	env -u DISPLAY -u WAYLAND_DISPLAY $(TEST_ENV) GLYCIN_TEST_BIG=$(abspath build/big.png) odin test glycin $(COLLECTIONS) $(TEST_FLAGS) -define:GLYCIN_VERSION=$(GLYCIN_VERSION) -define:ODIN_TEST_NAMES=glycin.test_oversized_image_is_refused -out:build/glycin_big_test

# Everything a push has to pass; CI (.github/workflows/ci.yml) runs the same.
ci: check test check-no-agent-files lint ## everything a push has to pass
	@echo 'CI OK'

generate: ## run runic over every package's rune.yml, then the post-processing rules
	@test -x $(RUNIC) || { echo "runic not found at $(RUNIC): see runic/amber-build.sh"; exit 2; }
	RUNIC=$(abspath $(RUNIC)) GLYCIN_STAGE=$(GLYCIN_STAGE) GTK_STAGE=$(GTK_STAGE) scripts/generate.sh

deps: ## check the tools and headers generation and tests need
	@test -x $(RUNIC) || echo "missing: runic at $(RUNIC) (build it with ../runic/amber-build.sh)"
	@command -v shellcheck >/dev/null || echo "missing: shellcheck (apt install shellcheck)"
	@command -v xvfb-run >/dev/null || echo "missing: xvfb-run (apt install xvfb)"
	@command -v bwrap >/dev/null || echo "missing: bwrap (apt install bubblewrap)"
	@command -v convert >/dev/null || echo "missing: convert (apt install imagemagick; the tests make their JPEG with it)"
	@for f in glycin-2 glycin-gtk4-2; do test -f $(GLYCIN_LIB)/pkgconfig/$$f.pc && echo "$$f $$(sed -n 's/^Version: //p' $(GLYCIN_LIB)/pkgconfig/$$f.pc)" || echo "missing: $$f (run 'make glycin' in ../amber-glycin)"; done

clean: ## remove build/
	rm -rf build

push: ## push the branch
	git push "$(REMOTE)" "$(BRANCH)"

# Agent files are never published. Two ways they get in: already tracked, or
# present-and-unignored when `git add -A` below sweeps the whole tree. Both are
# checked here, because a squashed history shows no file being added: a stray
# path appears in the root commit like any other file.
check-no-agent-files: ## refuse agent files that are tracked or not ignored
	@bad=$$(git ls-files | grep -E '(^|/)(\.mcp\.json|\.claude/|\.claude-amber/)' || true); \
	if [ -n "$$bad" ]; then \
		echo "agent files are tracked and must not be published:"; \
		printf '  %s\n' $$bad; \
		echo "fix: git rm -r --cached <path>, then add it to .gitignore"; \
		exit 2; \
	fi
	@for p in .mcp.json .claude .claude-amber; do \
		if [ -e "$$p" ] && ! git check-ignore -q "$$p"; then \
			echo "$$p exists and is not gitignored — 'git add -A' would publish it"; \
			echo "fix: add $$p to .gitignore"; \
			exit 2; \
		fi; \
	done
	@echo "no agent files staged for publication"

force-push: test check-no-agent-files ## squash history into one signed root commit and force-push
	@test -z "$$(git status --porcelain)" || { \
		echo "Working tree is dirty. Commit, stash, or revert changes first."; \
		exit 2; \
	}
	@set -e; \
	orig_branch="$$(git branch --show-current)"; \
	test -n "$$orig_branch" || { echo "force-push: detached HEAD, check out a branch first"; exit 1; }; \
	tmp_branch="root-squash-$$(date +%s)"; \
	step="starting"; ok=0; \
	trap 'if [ "$$ok" != 1 ]; then echo "force-push FAILED while: $$step. Local history is intact on $$orig_branch; $(REMOTE)/$(BRANCH) was not replaced." >&2; git checkout -f "$$orig_branch" >/dev/null 2>&1 || true; git branch -D "$$tmp_branch" >/dev/null 2>&1 || true; exit 1; fi' EXIT; \
	step="creating the orphan branch"; git checkout --orphan "$$tmp_branch"; \
	step="staging the tree"; git add -A; \
	step="signing the root commit"; git commit -S -m "$(ROOT_COMMIT_MSG)"; \
	step="pushing to $(REMOTE)/$(BRANCH) (refused or unreachable)"; git push --force "$(REMOTE)" "$$tmp_branch:$(BRANCH)"; \
	step="verifying $(REMOTE)/$(BRANCH) equals the new commit"; \
	remote_sha="$$(git ls-remote "$(REMOTE)" "refs/heads/$(BRANCH)" | cut -f1)"; \
	test -n "$$remote_sha" && test "$$remote_sha" = "$$(git rev-parse HEAD)"; \
	ok=1; \
	git branch -M "$$tmp_branch" "$(BRANCH)"; \
	git branch --set-upstream-to="$(REMOTE)/$(BRANCH)" "$(BRANCH)" >/dev/null 2>&1 || { git fetch "$(REMOTE)" "$(BRANCH)" >/dev/null 2>&1 && git branch --set-upstream-to="$(REMOTE)/$(BRANCH)" "$(BRANCH)" >/dev/null; } || echo "warning: could not set upstream"; \
	echo "Rewrote $$orig_branch as signed root commit on $(REMOTE)/$(BRANCH)."

# docs/API.md: every public declaration, from odin doc. check-api (in lint) fails when it is stale.
# scripts/api.sh takes the collection flags only; everything else is in scripts/api.conf.
api: ## regenerate docs/API.md
	scripts/api.sh $(COLLECTIONS) > docs/API.md

check-api: ## fail when docs/API.md is stale
	@mkdir -p build
	@scripts/api.sh $(COLLECTIONS) > build/API.md
	@cmp -s build/API.md docs/API.md || { echo 'docs/API.md is stale: run make api'; exit 1; }
	@echo "docs/API.md: current"

check-generated: ## fail when a va_list binding or a corrected [^]T parameter is back
	@scripts/check-generated.sh

check-cheatsheet-compile: ## compile every odin block of docs/CHEATSHEET.md
	@scripts/cheatsheet-compile.sh $(COLLECTIONS)

lint: ## shellcheck the shell scripts; generated-output guard; API and cheat sheet freshness
	@$(MAKE) --no-print-directory check-generated
	@$(MAKE) --no-print-directory check-api
	@scripts/cheatsheet.sh
	@$(MAKE) --no-print-directory check-cheatsheet-compile
	@if command -v shellcheck >/dev/null; then \
		git ls-files | while read -r f; do \
			case "$$f" in *.sh|*.bash) echo "$$f";; \
			*) head -1 "$$f" 2>/dev/null | grep -q '^#!.*sh' && echo "$$f";; esac; \
		done | xargs -r shellcheck --severity=warning && echo "shellcheck OK"; \
	else echo "shellcheck not installed — skipping (apt install shellcheck)"; fi

# `odin build` compiles a package's _test.odin files like any other file unless they
# start with #+test, so a test's imports and @(init) procs would ship in every program
# that imports the package.
check-test-tag: ## refuse _test.odin files without #+test
	@bad=$$(git ls-files --cached --others --exclude-standard '*_test.odin' | grep -Ev '(^|/)tests/' | xargs -r grep -L '^#+test' || true); \
	if [ -n "$$bad" ]; then \
		echo "test files without #+test, which odin build compiles into programs:"; \
		printf '  %s\n' $$bad; \
		exit 2; \
	fi

help: ## this list
	@awk 'BEGIN {FS = ":.*## "} \
	    /^##@ / {printf "\n%s\n", substr($$0, 5)} \
	    /^[a-z][a-z0-9-]*:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
