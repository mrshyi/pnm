SHELL := /usr/bin/env bash

.PHONY: test test-systemd test-real-cores syntax security-scan shellcheck release-check check

test:
	./tests/run.sh

# Explicit opt-in: creates only uniquely named temporary systemd test units.
test-systemd:
	PNM_RUN_SYSTEMD_TESTS=1 bash tests/integration/test_systemd_lifecycle.sh

# Explicit opt-in; requires separately acquired exact assets from the test manifest.
test-real-cores:
	PNM_RUN_REAL_CORE_TESTS=1 python3 tests/integration/test_real_cores.py

syntax:
	@find bin lib adapters tests -type f \( -name '*.sh' -o -path 'bin/pnm' \) | sort | while read -r file; do bash -n "$$file"; done
	@bash -n install.sh

security-scan:
	./tests/security-scan.sh

shellcheck:
	@command -v shellcheck >/dev/null 2>&1 || { echo 'shellcheck not installed'; exit 69; }
	shellcheck -x -S warning install.sh bin/pnm lib/*.sh adapters/*.sh

release-check:
	./tests/release-scan.sh
	$(MAKE) check

check: syntax security-scan test
