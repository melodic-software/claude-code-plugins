#!/usr/bin/env bash
# The fleet table reports a declared dependency present or missing and never installs.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-prerequisites.mjs"
NODE="$(command -v node)" || {
  echo "FAIL: node is not on PATH" >&2
  exit 1
}
FAILED=0
CASE_NUM=0
pass() { CASE_NUM=$((CASE_NUM + 1)); printf 'PASS: %s\n' "$1"; }
fail() { CASE_NUM=$((CASE_NUM + 1)); FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2; }
expect_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
expect_has() { if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

# entry <id> <need> [local_bin]: one schema-valid cli entry for plugin <id>'s check skill.
entry() {
  local lb=""
  [[ -n "${3:-}" ]] && lb=", \"local_bin\": [\"$3\"]"
  printf '{"id": "%s", "kind": "cli", "need": "%s", "for": ["plugin"], "detect": {"any": ["%s"]%s}, "degrade": "Without %s, the plugin does less.", "install": {"docs": "install %s"}, "check": "/plugin-x:check"}' \
    "$1" "$2" "$1" "$lb" "$1" "$1"
}
# manifest <dir> <plugin-name> <entry>...: write prerequisites.json and plugin.json.
manifest() {
  local dir="$1" name="$2" joined="" e
  shift 2
  for e in "$@"; do joined="${joined:+$joined,}$e"; done
  mkdir -p "$dir/.claude-plugin"
  printf '{"name":"%s"}\n' "$name" >"$dir/.claude-plugin/plugin.json"
  printf '{"requires":[%s]}\n' "$joined" >"$dir/prerequisites.json"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/node_modules/.bin"
manifest "$WORK/plugin-a" plugin-a "$(entry present-tool required)" "$(entry missing-tool required node_modules/.bin/missing-tool)"
cat >"$WORK/bin/present-tool" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$WORK/bin/present-tool"

out="$(cd "$WORK" && PATH="$WORK/bin:$PATH" "$NODE" "$SCRIPT" --plugin-root "$WORK/plugin-a")"
rc=$?
expect_eq "exit 1 when a required entry is missing" 1 "$rc"
expect_has "table header" $'plugin\tid\tkind\tneed\tstatus\tcheck\tinstall' "$out"
expect_has "present entry row" $'plugin-a\tpresent-tool\tcli\trequired\tpresent\t/plugin-x:check\tdocs: install present-tool' "$out"
expect_has "missing entry row" $'plugin-a\tmissing-tool\tcli\trequired\tmissing' "$out"
expect_has "summary counts" 'missing=1 present=1' "$out"

cat >"$WORK/node_modules/.bin/missing-tool" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$WORK/node_modules/.bin/missing-tool"
out="$(cd "$WORK" && PATH="$WORK/bin:$PATH" "$NODE" "$SCRIPT" --plugin-root "$WORK/plugin-a")"
rc=$?
expect_eq "exit 0 when the local bin is executable" 0 "$rc"
expect_has "local bin counts as present" 'missing=0 present=2' "$out"

manifest "$WORK/plugin-o" plugin-o "$(entry absent-optional optional)"
out="$("$NODE" "$SCRIPT" --plugin-root "$WORK/plugin-o")"
rc=$?
expect_eq "exit 0 when only an optional entry is missing" 0 "$rc"
expect_has "an optional entry is still listed as missing" $'plugin-o\tabsent-optional\tcli\toptional\tmissing' "$out"

mkdir -p "$WORK/plugin-bad/.claude-plugin"
printf '{"tools":[{"name":"x"}]}\n' >"$WORK/plugin-bad/prerequisites.json"
out="$("$NODE" "$SCRIPT" --plugin-root "$WORK/plugin-bad" 2>&1)"
rc=$?
expect_eq "a manifest in the retired shape exits 2" 2 "$rc"
expect_has "the schema failure names the plugin" 'plugin-bad: prerequisites.json fails the schema' "$out"

# Discovery with no roots. A plugin enabled only in the project's
# settings.local.json is read; a read state with nothing enabled is an empty
# fleet and never falls back to scanning a repository.
CONFIG="$WORK/config"
PROJECT="$WORK/project"
mkdir -p "$CONFIG/plugins" "$PROJECT/.claude"
manifest "$WORK/plugin-b" plugin-b "$(entry absent-b required)"
printf '{"plugins":{"plugin-b@m":[{"scope":"local","installPath":"%s"}]}}\n' "$WORK/plugin-b" >"$CONFIG/plugins/installed_plugins.json"
printf '%s\n' '{"enabledPlugins":{"plugin-b@m":false}}' >"$CONFIG/settings.json"
printf '%s\n' '{"enabledPlugins":{"plugin-b@m":true}}' >"$PROJECT/.claude/settings.local.json"
# NOCLAUDE_PATH holds only git, so no claude resolves and the settings fallback
# runs; STUB_PATH puts a stub claude ahead of it.
mkdir -p "$WORK/tools" "$WORK/stub"
ln -s "$(command -v git)" "$WORK/tools/git"
NOCLAUDE_PATH="$WORK/tools"
STUB_PATH="$WORK/stub:$WORK/tools"

out="$(cd "$PROJECT" && PATH="$NOCLAUDE_PATH" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" "$NODE" "$SCRIPT")"
rc=$?
expect_eq "project-local enablement is read" 1 "$rc"
expect_has "project-local plugin row" $'plugin-b\tabsent-b\tcli\trequired\tmissing' "$out"

rm "$PROJECT/.claude/settings.local.json"
manifest "$WORK/repo/plugins/plugin-c" plugin-c "$(entry absent-c required)"
git -C "$WORK/repo" init -q
out="$(cd "$WORK/repo" && PATH="$NOCLAUDE_PATH" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" "$NODE" "$SCRIPT")"
rc=$?
expect_eq "empty enabled fleet exits 0" 0 "$rc"
expect_has "empty enabled fleet prints an empty table" 'missing=0 present=0' "$out"

# With no settings or install state at all, the repository's plugins/ are scanned.
mkdir -p "$WORK/emptyconfig"
out="$(cd "$WORK/repo" && PATH="$NOCLAUDE_PATH" CLAUDE_CONFIG_DIR="$WORK/emptyconfig" CLAUDE_PROJECT_DIR="" "$NODE" "$SCRIPT")"
rc=$?
expect_eq "no state falls back to the repository scan" 1 "$rc"
expect_has "repository scan row" $'plugin-c\tabsent-c\tcli\trequired\tmissing' "$out"

mkdir -p "$WORK/notarepo"
out="$(cd "$WORK/notarepo" && PATH="$NOCLAUDE_PATH" CLAUDE_CONFIG_DIR="$WORK/emptyconfig" CLAUDE_PROJECT_DIR="" "$NODE" "$SCRIPT" 2>&1)"
rc=$?
expect_eq "no state and no repository exits 2" 2 "$rc"
expect_has "no state and no repository says so" 'no plugin roots to read' "$out"

# A settings file holding any non-Boolean enabledPlugins value contributes none
# of its keys, as Claude Code reads it: the string "false" never enables.
printf '%s\n' '{"enabledPlugins":{"plugin-b@m":"false"}}' >"$PROJECT/.claude/settings.local.json"
out="$(cd "$PROJECT" && PATH="$NOCLAUDE_PATH" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" "$NODE" "$SCRIPT")"
expect_has "fallback ignores a non-Boolean value" 'missing=0 present=0' "$out"
printf '%s\n' '{"enabledPlugins":{"plugin-b@m":true,"other@m":"yes"}}' >"$PROJECT/.claude/settings.local.json"
out="$(cd "$PROJECT" && PATH="$NOCLAUDE_PATH" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" "$NODE" "$SCRIPT")"
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
for n in d e f; do
  manifest "$WORK/plugin-$n" "plugin-$n" "$(entry "absent-$n" required)"
done
run_stub() { (cd "$PROJECT" && PATH="$STUB_PATH" STUB_LIST="$1" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" "$NODE" "$SCRIPT"); }

out="$(run_stub "[{\"id\":\"d@m\",\"scope\":\"user\",\"enabled\":true,\"installPath\":\"$WORK/plugin-d\"},
 {\"id\":\"e@m\",\"scope\":\"user\",\"enabled\":false,\"installPath\":\"$WORK/plugin-e\"}]")"
expect_has "cli: enabled user row is read" $'plugin-d\tabsent-d\tcli\trequired\tmissing' "$out"
expect_has "cli: disabled user row is not read" 'missing=1 present=0' "$out"

out="$(run_stub "[{\"id\":\"d@m\",\"scope\":\"project\",\"enabled\":true,\"installPath\":\"$WORK/plugin-d\",\"projectPath\":\"$PROJECT\"},
 {\"id\":\"e@m\",\"scope\":\"project\",\"enabled\":true,\"installPath\":\"$WORK/plugin-e\",\"projectPath\":\"$WORK/elsewhere\"},
 {\"id\":\"f@m\",\"scope\":\"local\",\"enabled\":true,\"installPath\":\"$WORK/plugin-f\",\"projectPath\":\"$PROJECT\"}]")"
expect_has "cli: project row for this project is read" $'plugin-d\tabsent-d\tcli\trequired\tmissing' "$out"
expect_has "cli: local row for this project is read" $'plugin-f\tabsent-f\tcli\trequired\tmissing' "$out"
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

# A listing larger than 200000 bytes must be read in full, and a listing that
# is not JSON must stop the run with no table. The stub reads its output from a
# file, since an environment variable that large would hit the argument limit.
mkdir -p "$WORK/stubfile"
cat >"$WORK/stubfile/claude" <<'EOF'
#!/bin/sh
[ "$1 $2 $3" = "plugin list --json" ] || exit 64
cat "$STUB_FILE"
EOF
chmod +x "$WORK/stubfile/claude"
ln -sf "$(command -v cat)" "$WORK/tools/cat"
run_stub_file() { (cd "$PROJECT" && PATH="$WORK/stubfile:$WORK/tools" STUB_FILE="$1" CLAUDE_CONFIG_DIR="$CONFIG" CLAUDE_PROJECT_DIR="$PROJECT" "$NODE" "$SCRIPT" 2>"$WORK/stderr"); }

# shellcheck disable=SC2016 # the JavaScript is single-quoted on purpose
"$NODE" -e '
const rows = Array.from({ length: 2500 }, (_, i) => ({ id: `pad${i}@m`, scope: "user", enabled: false, installPath: `/nonexistent/${i}`, note: "x".repeat(100) }));
rows.push({ id: "d@m", scope: "user", enabled: true, installPath: process.argv[2] });
require("node:fs").writeFileSync(process.argv[1], JSON.stringify(rows));
' "$WORK/big.json" "$WORK/plugin-d"
big_bytes="$(wc -c <"$WORK/big.json")"
expect_eq "oversized listing fixture exceeds 200000 bytes" 1 "$((big_bytes > 200000))"
out="$(run_stub_file "$WORK/big.json")"
rc=$?
expect_eq "oversized listing exits 1" 1 "$rc"
expect_has "oversized listing: the enabled row's entry is reported" $'plugin-d\tabsent-d\tcli\trequired\tmissing' "$out"
expect_has "oversized listing: summary counts it" 'missing=1 present=0' "$out"
expect_eq "oversized listing: nothing on stderr" "" "$(cat "$WORK/stderr")"

printf '%s\n' 'Error: something went wrong, not json' >"$WORK/bad.txt"
out="$(run_stub_file "$WORK/bad.txt")"
rc=$?
expect_eq "non-JSON listing exits 2" 2 "$rc"
expect_eq "non-JSON listing prints no table" "" "$out"
expect_has "non-JSON listing writes an error to stderr" 'claude plugin list --json' "$(cat "$WORK/stderr")"

out="$("$NODE" "$SCRIPT" --help 2>"$WORK/stderr")"
rc=$?
expect_eq "--help exits 0" 0 "$rc"
expect_has "--help prints the usage on stdout" 'check-prerequisites.mjs --plugin-root' "$out"
expect_has "--help lists the exit codes" '2 on a usage error' "$out"
expect_eq "--help writes nothing to stderr" "" "$(cat "$WORK/stderr")"

out="$("$NODE" "$SCRIPT" --bogus 2>&1)"
rc=$?
expect_eq "unknown argument exits 2" 2 "$rc"
expect_has "unknown argument names --help" '(see --help)' "$out"

out="$("$NODE" "$SCRIPT" --plugin-root 2>&1)"
rc=$?
expect_eq "--plugin-root without a directory exits 2" 2 "$rc"

# The reader depends on node alone: no python in the script, and a PATH without
# python still produces the table.
expect_eq "the script names no python" 0 "$(grep -ci python "$SCRIPT")"
out="$(PATH="$WORK/tools" "$NODE" "$SCRIPT" --plugin-root "$WORK/plugin-o")"
expect_has "the table prints with only node and git available" 'plugin-o' "$out"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
