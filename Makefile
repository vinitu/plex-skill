SHELL := /usr/bin/env bash

COMMAND_SCRIPTS := $(shell find scripts/commands -type f -name '*.sh' | sort)
INTERNAL_SCRIPTS := $(shell find scripts/lib -type f -name '*.sh' | sort)

.PHONY: check compile test

check:
	bash tests/dictionary_contract.sh

compile:
	bash -n $(COMMAND_SCRIPTS) $(INTERNAL_SCRIPTS) tests/smoke_plex.sh tests/dictionary_contract.sh tests/mocks/mock_curl.sh

test:
	bash tests/smoke_plex.sh
