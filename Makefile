SHELL := /usr/bin/env bash

.PHONY: test syntax security-scan shellcheck release-check check

test:
	./tests/run.sh

syntax:
	@find bin lib adapters tests -type f \( -name '*.sh' -o -path 'bin/pnm' \) | sort | while read -r file; do bash -n "$$file"; done

security-scan:
	./tests/security-scan.sh

shellcheck:
	@command -v shellcheck >/dev/null 2>&1 || { echo 'shellcheck not installed'; exit 69; }
	shellcheck -x -S warning bin/pnm lib/*.sh adapters/*.sh

release-check:
	./tests/release-scan.sh
	$(MAKE) check

check: syntax security-scan test
