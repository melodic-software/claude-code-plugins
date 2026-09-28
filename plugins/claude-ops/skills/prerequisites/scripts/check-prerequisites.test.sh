#!/usr/bin/env bash
# The fleet table reports a declared tool present or missing and never installs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-prerequisites.sh"
FAILED=0
CASE_NUM=0
pass() { CASE_NUM=$((CASE_NUM + 1)); printf 'PASS: %s\n' "$1"; }
fail() { CASE_NUM=$((CASE_NUM + 1)); FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2; }
expect_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
expect_has() { if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/plugin-a/.claude-plugin" "$WORK/bin" "$WORK/node_modules/.bin"
printf '%s\n' '{"name":"plugin-a"}' >"$WORK/plugin-a/.claude-plugin/plugin.json"
cat >"$WORK/plugin-a/prerequisites.json" <<'EOF'
{
  "tools": [
    {"name": "present-tool", "check": "/plugin-a:check", "install": "install present-tool"},
    {"name": "missing-tool", "local_bin": "node_modules/.bin/missing-tool", "check": "/plugin-a:check", "install": "install missing-tool"}
  ]
}
EOF
cat >"$WORK/bin/present-tool" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$WORK/bin/present-tool"

out="$(cd "$WORK" && PATH="$WORK/bin:$PATH" bash "$SCRIPT" --plugin-root "$WORK/plugin-a")"
rc=$?
expect_eq "exit 1 when a declared tool is missing" 1 "$rc"
expect_has "present tool row" $'present-tool\tplugin-a\tpresent\t/plugin-a:check\tinstall present-tool' "$out"
expect_has "missing tool row" $'missing-tool\tplugin-a\tmissing' "$out"
expect_has "summary counts" 'missing=1 present=1' "$out"

cat >"$WORK/node_modules/.bin/missing-tool" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$WORK/node_modules/.bin/missing-tool"
out="$(cd "$WORK" && PATH="$WORK/bin:$PATH" bash "$SCRIPT" --plugin-root "$WORK/plugin-a")"
rc=$?
expect_eq "exit 0 when the local bin is executable" 0 "$rc"
expect_has "local bin counts as present" 'missing=0 present=2' "$out"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
