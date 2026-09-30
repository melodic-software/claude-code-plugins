#!/usr/bin/env bash
# The fleet table reports a declared tool present or missing and never installs.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

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

# Discovery with no roots. A plugin enabled only in the project's
# settings.local.json is read; a read state with nothing enabled is an empty
# fleet and never falls back to scanning a repository.
CONFIG="$WORK/config"
PROJECT="$WORK/project"
mkdir -p "$CONFIG/plugins" "$PROJECT/.claude" "$WORK/plugin-b/.claude-plugin"
printf '%s\n' '{"name":"plugin-b"}' >"$WORK/plugin-b/.claude-plugin/plugin.json"
printf '%s\n' '{"tools":[{"name":"absent-b","check":"/plugin-b:check","install":"install absent-b"}]}' >"$WORK/plugin-b/prerequisites.json"
printf '{"plugins":{"plugin-b@m":[{"scope":"local","installPath":"%s"}]}}\n' "$WORK/plugin-b" >"$CONFIG/plugins/installed_plugins.json"
printf '%s\n' '{"enabledPlugins":{"plugin-b@m":false}}' >"$CONFIG/settings.json"
printf '%s\n' '{"enabledPlugins":{"plugin-b@m":true}}' >"$PROJECT/.claude/settings.local.json"
# NOCLAUDE_PATH holds only the tools the script needs, so no claude resolves and
# the settings fallback runs; STUB_PATH puts a stub claude ahead of them.
mkdir -p "$WORK/tools" "$WORK/stub"
for tool in bash git python3 dirname find sort timeout mktemp rm; do
  ln -s "$(command -v "$tool")" "$WORK/tools/$tool"
done
NOCLAUDE_PATH="$WORK/tools"
STUB_PATH="$WORK/stub:$WORK/tools"
export NOCLAUDE_PATH

out="$(cd "$PROJECT" && PATH="$NOCLAUDE_PATH" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" bash "$SCRIPT")"
rc=$?
expect_eq "project-local enablement is read" 1 "$rc"
expect_has "project-local plugin row" $'absent-b\tplugin-b\tmissing' "$out"

rm "$PROJECT/.claude/settings.local.json"
mkdir -p "$WORK/repo/plugins/plugin-c"
printf '%s\n' '{"tools":[{"name":"absent-c","check":"/plugin-c:check","install":"x"}]}' >"$WORK/repo/plugins/plugin-c/prerequisites.json"
git -C "$WORK/repo" init -q
out="$(cd "$WORK/repo" && PATH="$NOCLAUDE_PATH" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" bash "$SCRIPT")"
rc=$?
expect_eq "empty enabled fleet exits 0" 0 "$rc"
expect_has "empty enabled fleet prints an empty table" 'missing=0 present=0' "$out"

# A settings file holding any non-Boolean enabledPlugins value contributes none
# of its keys, as Claude Code reads it: the string "false" never enables.
printf '%s\n' '{"enabledPlugins":{"plugin-b@m":"false"}}' >"$PROJECT/.claude/settings.local.json"
out="$(cd "$PROJECT" && PATH="$NOCLAUDE_PATH" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" bash "$SCRIPT")"
expect_has "fallback ignores a non-Boolean value" 'missing=0 present=0' "$out"
printf '%s\n' '{"enabledPlugins":{"plugin-b@m":true,"other@m":"yes"}}' >"$PROJECT/.claude/settings.local.json"
out="$(cd "$PROJECT" && PATH="$NOCLAUDE_PATH" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" bash "$SCRIPT")"
expect_has "fallback skips the whole file when any value is non-Boolean" 'missing=0 present=0' "$out"
rm "$PROJECT/.claude/settings.local.json"

# With claude on PATH the enabled set comes from `claude plugin list --json`.
# The stub prints $STUB_LIST, so each case crafts the rows it needs.
cat >"$WORK/stub/claude" <<'EOF'
#!/bin/sh
[ "$1 $2 $3" = "plugin list --json" ] || exit 64
printf '%s' "$STUB_LIST"
EOF
chmod +x "$WORK/stub/claude"
mkdir -p "$WORK/plugin-d/.claude-plugin" "$WORK/plugin-e/.claude-plugin" "$WORK/plugin-f/.claude-plugin"
for n in d e f; do
  printf '{"name":"plugin-%s"}\n' "$n" >"$WORK/plugin-$n/.claude-plugin/plugin.json"
  printf '{"tools":[{"name":"absent-%s","check":"/plugin-%s:check","install":"x"}]}\n' "$n" "$n" >"$WORK/plugin-$n/prerequisites.json"
done
run_stub() { (cd "$PROJECT" && PATH="$STUB_PATH" STUB_LIST="$1" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" bash "$SCRIPT"); }

out="$(run_stub "[{\"id\":\"d@m\",\"scope\":\"user\",\"enabled\":true,\"installPath\":\"$WORK/plugin-d\"},
 {\"id\":\"e@m\",\"scope\":\"user\",\"enabled\":false,\"installPath\":\"$WORK/plugin-e\"}]")"
expect_has "cli: enabled user row is read" $'absent-d\tplugin-d\tmissing' "$out"
expect_has "cli: disabled user row is not read" 'missing=1 present=0' "$out"

out="$(run_stub "[{\"id\":\"d@m\",\"scope\":\"project\",\"enabled\":true,\"installPath\":\"$WORK/plugin-d\",\"projectPath\":\"$PROJECT\"},
 {\"id\":\"e@m\",\"scope\":\"project\",\"enabled\":true,\"installPath\":\"$WORK/plugin-e\",\"projectPath\":\"$WORK/elsewhere\"},
 {\"id\":\"f@m\",\"scope\":\"local\",\"enabled\":true,\"installPath\":\"$WORK/plugin-f\",\"projectPath\":\"$PROJECT\"}]")"
expect_has "cli: project row for this project is read" $'absent-d\tplugin-d\tmissing' "$out"
expect_has "cli: local row for this project is read" $'absent-f\tplugin-f\tmissing' "$out"
expect_has "cli: a project row with a foreign projectPath is ignored" 'missing=2 present=0' "$out"

out="$(run_stub "[{\"id\":\"d@m\",\"scope\":\"user\",\"enabled\":true,\"installPath\":\"$WORK/plugin-d\"},
 {\"id\":\"d@m\",\"scope\":\"project\",\"enabled\":false,\"installPath\":\"$WORK/plugin-d\",\"projectPath\":\"$PROJECT\"}]")"
expect_has "cli: user enabled but project disabled resolves to disabled" 'missing=0 present=0' "$out"

out="$(run_stub "[{\"id\":\"d@m\",\"scope\":\"user\",\"enabled\":false,\"installPath\":\"$WORK/plugin-d\"},
 {\"id\":\"d@m\",\"scope\":\"project\",\"enabled\":true,\"installPath\":\"$WORK/plugin-d\",\"projectPath\":\"$PROJECT\"}]")"
expect_has "cli: user disabled but project enabled resolves to enabled" 'missing=1 present=0' "$out"

out="$(run_stub "[]")"
rc=$?
expect_eq "cli: an empty list is an empty fleet, not a repository scan" 0 "$rc"

# Unparsable claude output is an error, not a settings fallback.
printf '%s\n' '{"enabledPlugins":{"plugin-b@m":true}}' >"$PROJECT/.claude/settings.local.json"
out="$(run_stub "not json" 2>&1)"
rc=$?
expect_eq "unparsable claude output exits 2" 2 "$rc"
expect_has "unparsable claude output names the listing" 'claude plugin list --json' "$out"
rm "$PROJECT/.claude/settings.local.json"

# A listing past the 131072-byte single-argument limit must be read in full,
# and a listing that is not JSON must stop the run with no table. The stub
# reads its output from a file, since an environment variable that large would
# hit the same limit.
mkdir -p "$WORK/stubfile"
cat >"$WORK/stubfile/claude" <<'EOF'
#!/bin/sh
[ "$1 $2 $3" = "plugin list --json" ] || exit 64
cat "$STUB_FILE"
EOF
chmod +x "$WORK/stubfile/claude"
ln -sf "$(command -v cat)" "$WORK/tools/cat"
run_stub_file() { (cd "$PROJECT" && PATH="$WORK/stubfile:$WORK/tools" STUB_FILE="$1" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" bash "$SCRIPT" 2>"$WORK/stderr"); }

python3 - "$WORK/big.json" "$WORK/plugin-d" <<'PY'
import json, sys
rows = [{"id": "pad%d@m" % i, "scope": "user", "enabled": False, "installPath": "/nonexistent/%d" % i, "note": "x" * 100} for i in range(2500)]
rows.append({"id": "d@m", "scope": "user", "enabled": True, "installPath": sys.argv[2]})
json.dump(rows, open(sys.argv[1], "w"))
PY
big_bytes="$(wc -c <"$WORK/big.json")"
expect_eq "oversized listing fixture exceeds 200000 bytes" 1 "$((big_bytes > 200000))"
out="$(run_stub_file "$WORK/big.json")"
rc=$?
expect_eq "oversized listing exits 1" 1 "$rc"
expect_has "oversized listing: the enabled row's tool is reported" $'absent-d\tplugin-d\tmissing' "$out"
expect_has "oversized listing: summary counts it" 'missing=1 present=0' "$out"
expect_eq "oversized listing: no argument-length error" 0 "$(grep -c 'Argument list too long' "$WORK/stderr")"

printf '%s\n' 'Error: something went wrong, not json' >"$WORK/bad.txt"
out="$(run_stub_file "$WORK/bad.txt")"
rc=$?
expect_eq "non-JSON listing exits 2" 2 "$rc"
expect_eq "non-JSON listing prints no table" "" "$out"
expect_has "non-JSON listing writes an error to stderr" 'claude plugin list --json' "$(cat "$WORK/stderr")"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
