#!/usr/bin/env bash
# A .gitleaks.toml at the root and no cross-cutting record; every other ecosystem disabled. A text
# file changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude docs .gitleaks.toml
eval_eco_off dotnet python typescript bash powershell markdown go yaml
mkdir -p docs
printf '[extend]\nuseDefault = true\n' >.gitleaks.toml
printf 'Rotate keys every quarter.\n' >docs/keys.txt
g add -A
g commit -q -m "agent docs"
printf 'Rotate keys every quarter and after staff changes.\n' >docs/keys.txt
