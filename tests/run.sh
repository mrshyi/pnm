#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

failed=0
for test_name in \
    test_accounts.sh test_assets.sh test_check.sh test_cli.sh test_core_ops.sh \
    test_config.sh test_deploy.sh test_host_apply.sh test_lifecycle.sh test_lock.sh test_node.sh \
    test_render.sh test_sandbox_install.sh test_service.sh \
    test_staging.sh test_tls.sh test_transaction.sh; do
    test_file="$TEST_ROOT/unit/$test_name"
    printf '# %s\n' "$(basename -- "$test_file")"
    if ! "$test_file"; then
        failed=1
    fi
done

exit "$failed"
