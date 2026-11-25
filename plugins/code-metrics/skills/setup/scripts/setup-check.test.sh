#!/usr/bin/env bash
# test-scope: plugins/code-metrics/scripts/*
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/setup-check.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
: "$SCRIPT_DIR/setup-apply.py"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$(printf '%s' "$2" | head -c 600)" ;;
  esac
}
assert_row() {
  if grep -Eq -- "$3" <<<"$2"; then
    pass "$1"
  else
    fail "$1" "matches: $3" "$(printf '%s' "$2" | head -c 600)"
  fi
}

home="$(mktemp -d)"
repo="$(mktemp -d)"
trap 'rm -rf "$home" "$repo"' EXIT

out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
rc=$?
assert_eq "no config exits 0" 0 "$rc"
assert_contains "the userConfig layer is named" "$out" "INFO  layer userConfig"
if grep -q "layer user-global" <<<"$out"; then
  fail "no old user-global file, no user-global row" "no layer user-global row" "$(printf '%s' "$out" | head -c 600)"
else
  pass "no old user-global file, no user-global row"
fi
assert_row "the personal layer is the docs file" "$out" "INFO  layer local +absent \($repo/docs/conventions/code-metrics.local.yaml\)"
assert_contains "team layer absent" "$out" "INFO  layer team"
assert_row "bundled default reference" "$out" "reference file_lines +1000 \(layer: bundled default\)"
adapters="$(find "$PLUGIN_ROOT/scripts/collectors" -maxdepth 1 -name '*.py' ! -name 'test_*' ! -name 'adapter_paths.py' | wc -l | tr -d ' ')"
rows="$(printf '%s\n' "$out" | grep -c '  collector ')"
assert_eq "one row per collector adapter" "$adapters" "$rows"
rows_helper="$(printf '%s\n' "$out" | grep -c 'collector adapter_paths' || true)"
assert_eq "no row for the adapter_paths helper" 0 "$rows_helper"
assert_row "the bundled counter measures a fixture" "$out" "PASS  collector line-counter +bundled; measured file_lines on cm-sample.ts"
assert_contains "python row" "$out" "PASS  python"

(cd "$repo" && git init -q -b main && git config user.email t@example.com && git config user.name t)
python3 "$SCRIPT_DIR/setup-apply.py" --dir "$repo" size.file_lines=500 >/dev/null
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
assert_row "team layer parses" "$out" "PASS  layer team +$repo/docs/conventions/code-metrics.yaml parses"
assert_row "untracked team file warns" "$out" "WARN  layer team tracked +written but untracked"
assert_row "reference from the team layer" "$out" "reference file_lines +500 \(layer: team\)"
(cd "$repo" && git add docs && git commit -q -m config)
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
assert_row "committed team file passes" "$out" "PASS  layer team tracked +committed"

retired_repo="$(mktemp -d)"
mkdir -p "$retired_repo/.claude"
printf 'size:\n  file_lines: 420\n' >"$retired_repo/.claude/code-metrics.yaml"
out="$(bash "$SCRIPT" --repo-root "$retired_repo" --home "$home")"
rm -rf "$retired_repo"
assert_row "a retired team file alone leaves the team layer absent" "$out" "INFO  layer team +absent"
assert_row "the retired team file location warns" "$out" "WARN  layer team location +.*is not read; .*setup apply moves its keys"
assert_row "the retired team file supplies no reference" "$out" "reference file_lines +1000 \(layer: bundled default\)"
home_repo="$(mktemp -d)"
mkdir -p "$home_repo/.claude"
printf 'size:\n  file_lines: 430\n' >"$home_repo/.claude/code-metrics.yaml"
out="$(bash "$SCRIPT" --repo-root "$home_repo" --home "$home_repo")"
rm -rf "$home_repo"
assert_row "a home-root user-global file is read" "$out" "reference file_lines +430 \(layer: userConfig\)"
if grep -q "layer team location" <<<"$out"; then
  fail "a home-root user-global file is not called retired" "no layer team location row" "$(printf '%s' "$out" | head -c 600)"
else
  pass "a home-root user-global file is not called retired"
fi

(cd "$repo" && git rm -q --cached docs/conventions/code-metrics.yaml && git commit -q -m untrack)
printf 'docs/conventions/code-metrics.yaml\n' >"$repo/.gitignore"
mkdir -p "$repo/.claude"
printf 'size:\n  file_lines: 7\n' >"$repo/.claude/code-metrics.local.yaml"
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
rc=$?
assert_eq "ignored team file exits 1" 1 "$rc"
assert_contains "ignored team file fails" "$out" "FAIL  layer team tracked"
assert_contains "unignored personal override warns with the gitignore line" "$out" ".claude/**/*.local.*"
assert_row "an old personal file alone is read and named" "$out" "WARN  layer local location +$repo/.claude/code-metrics.local.yaml is the old personal override, still read"
assert_row "an old personal file alone supplies its values" "$out" "reference file_lines +7 \(layer: local\)"
rm -f "$repo/.gitignore"
printf 'size:\n  file_lines: 8\n' >"$repo/docs/conventions/code-metrics.local.yaml"
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
assert_row "with both personal files the new one wins" "$out" "reference file_lines +8 \(layer: local\)"
assert_row "with both personal files the warning names both" "$out" "WARN  layer local location +$repo/.claude/code-metrics.local.yaml is the old personal override and is not read because $repo/docs/conventions/code-metrics.local.yaml exists"
assert_contains "the new personal file warns with its gitignore line" "$out" "docs/conventions/**/*.local.*"
printf 'size: { file_lines: 1 }\n' >"$repo/docs/conventions/code-metrics.local.yaml"
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
assert_row "a new personal file outside the subset leaves the old one read" "$out" "WARN  layer local location +$repo/.claude/code-metrics.local.yaml is the old personal override, still read because $repo/docs/conventions/code-metrics.local.yaml is outside the YAML subset"
assert_row "the old personal file read in its place is parse-checked" "$out" "PASS  layer local +$repo/.claude/code-metrics.local.yaml parses"
assert_row "the new personal file outside the subset fails" "$out" "FAIL  layer local +$repo/docs/conventions/code-metrics.local.yaml is outside the YAML subset"
assert_row "the old personal file supplies its values" "$out" "reference file_lines +7 \(layer: local\)"
printf 'size:\n  file_lines: 8\n' >"$repo/docs/conventions/code-metrics.local.yaml"
rm -f "$repo/.claude/code-metrics.local.yaml"
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
assert_row "the new personal file alone is read" "$out" "reference file_lines +8 \(layer: local\)"
if grep -q "layer local location" <<<"$out"; then
  fail "the new personal file alone gets no old-path row" "no layer local location row" "$(printf '%s' "$out" | head -c 600)"
else
  pass "the new personal file alone gets no old-path row"
fi
rm -f "$repo/docs/conventions/code-metrics.local.yaml"
mkdir -p "$home/.claude"
printf 'complexity:\n  cyclomatic:\n    reference: 11\n' >"$home/.claude/code-metrics.yaml"
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
assert_row "an old user-global file alone is named" "$out" "WARN  layer user-global location +$home/.claude/code-metrics.yaml is the old user-global file, still read"
assert_contains "an old user-global file points at the option" "$out" "copies its keys to the file the config_file userConfig option names (set it in /config)"
assert_row "an old user-global file supplies the userConfig layer" "$out" "reference cyclomatic +11 \(layer: userConfig\)"
assert_row "the option unset is named" "$out" "INFO  layer userConfig +unset: the config_file option names no file"
user_file="$home/cfg/code-metrics.yaml"
printf -v tilde_user_file '%s/cfg/code-metrics.yaml' '~'
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home" --user-file "$tilde_user_file")"
assert_row "an option naming a missing file leaves the old file read" "$out" "reference cyclomatic +11 \(layer: userConfig\)"
assert_contains "the old-file row names the option's file" "$out" "copies its keys to $user_file"
mkdir -p "$home/cfg"
printf 'complexity:\n  cyclomatic:\n    reference: 13\n' >"$user_file"
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home" --user-file "$tilde_user_file")"
assert_row "with both user files the option's file wins" "$out" "reference cyclomatic +13 \(layer: userConfig\)"
assert_row "with both user files the warning names both" "$out" "WARN  layer user-global location +$home/.claude/code-metrics.yaml is the old user-global file and is not read because $user_file exists"
assert_row "the option's file is parse-checked" "$out" "PASS  layer userConfig +$user_file parses"
rm -f "$home/.claude/code-metrics.yaml"
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home" --user-file "$user_file")"
assert_row "the option's file alone supplies its values" "$out" "reference cyclomatic +13 \(layer: userConfig\)"
if grep -q "layer user-global location" <<<"$out"; then
  fail "the option's file alone gets no old-path row" "no layer user-global location row" "$(printf '%s' "$out" | head -c 600)"
else
  pass "the option's file alone gets no old-path row"
fi
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home" --user-file "cfg/code-metrics.yaml")"
assert_row "a relative option is a warning" "$out" "WARN  layer userConfig +the config_file option 'cfg/code-metrics.yaml' is not an absolute path"
assert_row "a relative option supplies no layer" "$out" "reference cyclomatic +20 \(layer: bundled default\)"
rm -rf "$home/cfg"

mkdir -p "$home/.claude"
printf 'languages:\n  typescript: { enabled: true }\n' >"$home/.claude/code-metrics.yaml"
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
rc=$?
assert_eq "bad layer exits 1" 1 "$rc"
assert_contains "bad layer names the construct" "$out" "FAIL  layer userConfig"
assert_contains "bad layer names the line" "$out" "line 2"

fake="$(mktemp -d)"
trap 'rm -rf "$home" "$repo" "$fake"' EXIT
cp -R "$PLUGIN_ROOT/scripts" "$fake/scripts"
stub_counter() {
  printf '%s\n' 'import sys' \
    'if sys.argv[1] == "probe":' '    print("bundled")' \
    'elif sys.argv[1] == "collect":' "    $1" >"$fake/scripts/collectors/line-counter.py"
}
stub_counter 'print("boom", file=sys.stderr); sys.exit(1)'
out="$(CLAUDE_PLUGIN_ROOT="$fake" bash "$SCRIPT" --repo-root "$repo" --home "$home")"
rc=$?
assert_eq "a probe-only collector exits 1" 1 "$rc"
assert_row "a failed measure is FAIL with its stderr" "$out" "FAIL  collector line-counter +bundled; probe passed but collect typescript file_lines on cm-sample.ts failed \(exit 1\): boom"
stub_counter 'pass'
out="$(CLAUDE_PLUGIN_ROOT="$fake" bash "$SCRIPT" --repo-root "$repo" --home "$home")"
assert_row "a measure with no rows is FAIL" "$out" "FAIL  collector line-counter +bundled; probe passed but collect typescript file_lines on cm-sample.ts returned no rows"
stub_counter 'print("no config", file=sys.stderr); sys.exit(4)'
out="$(CLAUDE_PLUGIN_ROOT="$fake" bash "$SCRIPT" --repo-root "$repo" --home "$fake")"
rc=$?
assert_eq "a tool that cannot run here exits 0" 0 "$rc"
assert_row "exit 4 is WARN probe only" "$out" "WARN  collector line-counter +bundled; probe only: no config"

mkdir -p "$repo/node_modules/.bin"
printf '#!/bin/sh\n' >"$repo/node_modules/.bin/projtool"
chmod +x "$repo/node_modules/.bin/projtool"
stub_counter 'import shutil; ok = shutil.which("projtool"); print("{}") if ok else sys.exit(1)'
out="$(cd "$repo" && CLAUDE_PLUGIN_ROOT="$fake" bash "$SCRIPT" --repo-root "$repo" --home "$home")"
assert_row "a project-local tool resolves from the fixture directory" "$out" "PASS  collector line-counter"

printf '%s\n' 'import sys' \
  'if sys.argv[1] == "probe":' '    sys.exit(1)' \
  'elif sys.argv[1] == "install_hint":' '    print("install the stub tool")' >"$fake/scripts/collectors/line-counter.py"
out="$(CLAUDE_PLUGIN_ROOT="$fake" bash "$SCRIPT" --repo-root "$repo" --home "$fake")"
rc=$?
assert_eq "a missing collector exits 0" 0 "$rc"
assert_row "a missing probe is an INFO missing row with its hint" "$out" "INFO  collector line-counter +missing; install the stub tool"

eco_repo="$(mktemp -d)"
trap 'rm -rf "$home" "$repo" "$fake" "$eco_repo"' EXIT
mkdir -p "$eco_repo/.claude/ecosystems"
printf 'globs:\n  - "**/*.py"\n' >"$eco_repo/.claude/ecosystems/python.yaml"
printf 'globs:\n  - "**/*.rs"\n' >"$eco_repo/.claude/ecosystems/rust.yaml"
out="$(bash "$SCRIPT" --repo-root "$eco_repo" --home "$fake")"
rc=$?
assert_eq "an unlisted ecosystem record does not fail the run" 0 "$rc"
assert_row "a listed language's record is honored" "$out" "PASS  ecosystem python.yaml +parses; its globs and enabled key are honored for language detection"
assert_row "an unlisted language's record is not used" "$out" "WARN  ecosystem rust.yaml +parses, but no layer lists language rust under languages, so it is not used for language detection; add a languages.rust entry"
mkdir -p "$eco_repo/docs/conventions"
printf 'languages:\n  rust:\n    enabled: true\n' >"$eco_repo/docs/conventions/code-metrics.yaml"
out="$(bash "$SCRIPT" --repo-root "$eco_repo" --home "$fake")"
assert_row "a language a layer lists honors its record" "$out" "PASS  ecosystem rust.yaml +parses; its globs and enabled key are honored for language detection"
printf 'globs:\n  - "**/*.zig"\n' >"$eco_repo/.claude/ecosystems/Zig.yaml"
out="$(bash "$SCRIPT" --repo-root "$eco_repo" --home "$fake")"
assert_row "an invalid language id asks for a rename" "$out" "WARN  ecosystem Zig.yaml +parses, but its file name gives language id Zig, which is not lowercase kebab-case, so no language can read it; rename the file"
if grep -q "languages.Zig" <<<"$out"; then
  fail "an invalid language id gets no languages entry advice" "no languages.Zig" "$(printf '%s' "$out" | head -c 600)"
else
  pass "an invalid language id gets no languages entry advice"
fi
rm "$eco_repo/.claude/ecosystems/Zig.yaml"
mkdir -p "$eco_repo/docs/conventions/ecosystems"
printf 'globs:\n  - "**/*.rs"\n' >"$eco_repo/docs/conventions/ecosystems/rust.yaml"
out="$(bash "$SCRIPT" --repo-root "$eco_repo" --home "$fake")"
assert_row "a record at the convention home is honored" "$out" "PASS  ecosystem rust.yaml +parses; its globs and enabled key are honored for language detection"
assert_row "a legacy record the convention home shadows asks for its removal" "$out" "WARN  ecosystem .claude/ecosystems/rust.yaml +is not read: docs/conventions/ecosystems/rust.yaml takes its place; delete it"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
