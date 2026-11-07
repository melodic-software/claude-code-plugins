#!/usr/bin/env bash
# A Go module whose tracked go.yaml routes fix-cmd and code-fix-cmd through tools/run.sh, which logs
# each call's arguments to .calls.log. pkg/a.go, go.mod and go.sum changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude tools pkg go.mod go.sum
eval_logger
eval_eco go '["*.go", "go.mod", "go.sum"]' check fix code-fix
mkdir -p pkg
printf 'module example.com/shop\n\ngo 1.24\n' >go.mod
printf '' >go.sum
printf 'package pkg\n\nfunc A() int { return 1 }\n' >pkg/a.go
g add -A
g commit -q -m "shop module"
printf 'module example.com/shop\n\ngo 1.24\n\nrequire example.com/money v1.2.0\n' >go.mod
printf 'example.com/money v1.2.0 h1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' >go.sum
printf 'package pkg\n\nfunc A() int {   return 2 }\n' >pkg/a.go
