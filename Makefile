ARENA_DIR ?= _deps/lean-kernel-arena
CHECKER ?= rocq-lean-import
TEST ?= sparse-name-index
ROCQLKA_OPAM_SWITCH ?= rocq93_dev
LKA ?= python3 lka.py
LKA_PATH := $(CURDIR)/scripts/no-perf:$(PATH)

.PHONY: bootstrap build-checker build-test run smoke

bootstrap:
	./scripts/bootstrap_arena.sh

build-checker: bootstrap
	cd $(ARENA_DIR) && PATH="$(LKA_PATH)" ROCQLKA_OPAM_SWITCH=$(ROCQLKA_OPAM_SWITCH) $(LKA) build-checker '$(CHECKER)'

build-test: bootstrap
	cd $(ARENA_DIR) && PATH="$(LKA_PATH)" $(LKA) build-test '$(TEST)'

run: build-checker
	cd $(ARENA_DIR) && PATH="$(LKA_PATH)" ROCQLKA_OPAM_SWITCH=$(ROCQLKA_OPAM_SWITCH) $(LKA) run --checker '$(CHECKER)' --test '$(TEST)'

smoke: build-checker build-test run
