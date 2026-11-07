#!/usr/bin/env bash
# A Go module whose tracked go.yaml routes code-fix-cmd through tools/run.sh, which logs each
# call's arguments as one line of .calls.log. pkg/a/a.go, pkg/b/b.go and go.mod changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude tools pkg go.mod .golangci.yml
eval_logger
eval_eco go '["*.go", "go.mod", "go.sum"]' check fix code-fix
# lint SKILL.md's per-directory split applies to `golangci-lint run --fix`, so code-fix-cmd runs
# through a golangci-lint shim that hands the files to the logger as `go code-fix <files>`.
cat >tools/golangci-lint <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == run && "${2:-}" == --fix ]] || { echo "golangci-lint shim: only 'run --fix' is supported" >&2; exit 2; }
shift 2
exec bash "$(dirname "${BASH_SOURCE[0]}")/run.sh" go code-fix "$@"
EOF
chmod +x tools/golangci-lint
sed -i 's|^code-fix-cmd: .*|code-fix-cmd: "bash tools/golangci-lint run --fix <files>"|' .claude/ecosystems/go.yaml
# The repository opts in to golangci-lint with its own config, so the lint skill's opt-in holds.
printf 'version: "2"\nlinters:\n  default: standard\n' >.golangci.yml
mkdir -p pkg/a pkg/b
printf 'module example.com/shop\n\ngo 1.24\n' >go.mod
printf 'package a\n\nfunc A() int { return 1 }\n' >pkg/a/a.go
printf 'package b\n\nfunc B() int { return 1 }\n' >pkg/b/b.go
g add -A
g commit -q -m "shop module"
printf 'module example.com/shop\n\ngo 1.25\n' >go.mod
printf 'package a\n\nimport "fmt"\n\nfunc A() int { return 2 }\n' >pkg/a/a.go
printf 'package b\n\nimport "os"\n\nfunc B() int { return 2 }\n' >pkg/b/b.go
