#!/usr/bin/env bash
# Tracked yaml and cross-cutting configs whose check commands log to .calls.log, a typos config at
# the root, and every other ecosystem disabled. A workflow YAML and several text files changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude .github tools docs _typos.toml
eval_logger
eval_eco yaml '[".github/**/*.yml", ".github/**/*.yaml"]' check
eval_eco cross-cutting '["**"]' check
eval_eco_off dotnet python typescript bash powershell markdown go
mkdir -p .github/workflows docs
printf '[default.extend-words]\nfabrikam = "fabrikam"\n' >_typos.toml
printf 'name: ci\non: [pull_request]\njobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo test\n' >.github/workflows/ci.yml
printf 'Install the agent, then start it.\n' >docs/install.txt
printf 'Rotate keys every quarter.\n' >docs/keys.txt
g add -A
g commit -q -m "agent docs"
printf 'name: ci\non: [pull_request]\njobs:\n  test:\n    runs-on: ubuntu-24.04\n    timeout-minutes: 10\n    steps:\n      - run: echo test\n' >.github/workflows/ci.yml
printf 'Install the agent, then start it with the service manager.\n' >docs/install.txt
printf 'Rotate keys every quarter and after staff changes.\n' >docs/keys.txt
