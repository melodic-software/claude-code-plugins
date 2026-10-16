#!/usr/bin/env bash
# Black-box contract test for the bash-format PostToolBatch row, launched exactly
# as hooks.json registers it (node exec-bash.mjs with the row's args).
#
# Proves WIRING: one PostToolBatch row and no PostToolUse row; the row formats the
# .sh and .bash files a Write, Edit or MultiEdit in the batch named, once per
# batch, and never anything a Read named; it prints nothing (no finding, no
# disclosure reaches the model) and exits 0; an .editorconfig section naming shell
# files must govern the file (present -> format, absent or a bare [*] -> leave the
# bytes untouched); an array-subscript rewrite is put back; a shfmt that lacks
# --apply-ignore still formats, and one that fails a run or its probe does not
# re-run without the flag; .githooks/, gitignored files, an ignore = true section
# and the kill switch are honored; a batch with no shell edit costs only the
# launcher.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures. The
# row is run from an UNRELATED cwd so any reliance on the caller's working
# directory would surface. Requires shfmt and jq; without them the behavioral
# assertions cannot run, so the suite skips them.
# test-scope: plugins/bash-format/.claude-plugin/plugin.json plugins/bash-format/hooks/hooks.json plugins/bash-format/prerequisites.json plugins/bash-format/git-hooks/shfmt-rewrite.sh

# shellcheck disable=SC2016 # fixtures hold literal shell text, not expansions
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${HOOK_DIR%/*}"
HOOKS_JSON="$HOOK_DIR/hooks.json"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1: want [$2] got [$3]"; fi
}

# --- The manifest lists the plugin's tools -----------------------------------
MANIFEST="$PLUGIN_ROOT/prerequisites.json"
if command -v jq >/dev/null 2>&1 && [[ -f "$MANIFEST" ]]; then
  if jq -e '(.requires | map(.id) | sort) == ["jq", "node", "shellcheck", "shfmt"]' "$MANIFEST" >/dev/null 2>&1; then
    ok "manifest: declares exactly shfmt, shellcheck, jq and node"
  else
    fail "manifest: expected tools shfmt, shellcheck, jq and node: $(cat "$MANIFEST")"
  fi
else
  fail "manifest check needs jq and $MANIFEST"
fi

# --- hooks.json: one PostToolBatch row, an opt-in Stop row, no PostToolUse ---
# The batch row takes no matcher and no `if`: the hooks reference says neither
# applies to the event, so its launcher flag is the only filter. The flag's text
# is the closing quote of a JSON string ending in "sh", which both extensions
# do; the script reads the paths itself.
if command -v jq >/dev/null 2>&1 && [[ -f "$HOOKS_JSON" ]]; then
  # shellcheck disable=SC2016 # the CLAUDE_PLUGIN_ROOT placeholders are literal manifest text
  EXPECTED_ROW='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","BASH_FORMAT_ENABLED","--skip-unless-stdin-contains","sh\"","${CLAUDE_PLUGIN_ROOT}/hooks/bash-format.sh"]'
  expect "hooks.json: no PostToolUse row" "0" "$(jq '[.hooks.PostToolUse // [] | .[]] | length' "$HOOKS_JSON")"
  expect "hooks.json: no digest-reset SessionStart row" "0" "$(jq '[.hooks.SessionStart[].hooks[].args // [] | .[] | select(. == "--reset-digests")] | length' "$HOOKS_JSON")"
  expect "hooks.json: one PostToolBatch group with one handler" "1 1" "$(jq -r '.hooks.PostToolBatch | "\(length) \(.[0].hooks | length)"' "$HOOKS_JSON")"
  expect "hooks.json: the batch handler has no matcher, no if, and runs the script behind the prefilter" \
    "node true true $EXPECTED_ROW" \
    "$(jq -r '.hooks.PostToolBatch[0] as $g | $g.hooks[0] | "\(.command) \($g | has("matcher") | not) \(has("if") | not) \(.args | tojson)"' "$HOOKS_JSON")"
  # shellcheck disable=SC2016
  EXPECTED_STOP='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","BASH_FORMAT_ENABLED","--require-true","BASH_FORMAT_END_OF_TURN","${CLAUDE_PLUGIN_ROOT}/hooks/bash-format.sh","--end-of-turn"]'
  expect "hooks.json: the Stop row is gated on the end-of-turn option" "$EXPECTED_STOP" "$(jq -c '.hooks.Stop[0].hooks[0].args' "$HOOKS_JSON")"
  expect "plugin.json: the end-of-turn option is declared, default false" "boolean false" \
    "$(jq -r '.userConfig.bash_format_end_of_turn | "\(.type) \(.default)"' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
else
  fail "hooks.json assertions need jq and $HOOKS_JSON"
fi

# --- SessionStart probe honors bash_format_enabled ---------------------------
# Runs the hooks.json SessionStart row as the harness spawns it: `node` with the
# row's args, ${CLAUDE_PLUGIN_ROOT} expanded, from an empty cwd, on a PATH that
# holds the system tools and none of shfmt, shellcheck and jq. The gate is
# `--run-if-unset-or-true` in exec-bash.mjs, so a row without it prints the
# notice for a disabled plugin. A missing node fails the suite instead of
# skipping the cases: every hook row launches through it.
NODE_BIN="$(command -v node 2>/dev/null)"
if [[ -z "$NODE_BIN" ]]; then
  fail "probe-gate: node is not on PATH, and every hook row launches through node hooks/exec-bash.mjs"
else
  PG_WORK="$(mktemp -d)"
  mkdir -p "$PG_WORK/sysbin" "$PG_WORK/cwd"
  for dir in /usr/local/bin /usr/bin /bin; do
    for exe in "$dir"/*; do
      base="${exe##*/}"
      [[ -x "$exe" && "$base" != shfmt && "$base" != shellcheck && "$base" != jq && ! -e "$PG_WORK/sysbin/$base" ]] || continue
      MSYS=winsymlinks:nativestrict ln -s "$exe" "$PG_WORK/sysbin/$base"
    done
  done
  PG_ARGS=()
  while IFS= read -r pg_arg; do
    # shellcheck disable=SC2016  # the placeholder is matched literally, as Claude Code substitutes it
    PG_ARGS+=("${pg_arg//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_ROOT}")
  done < <(jq -r '.hooks.SessionStart[0].hooks[0].args[]' "$HOOKS_JSON")

  # run_probe <value|__unset__> -> run the row with bash_format_enabled set to <value> (or unset).
  run_probe() {
    local v="$1"
    local -a opt=(env -u CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED)
    [[ "$v" == "__unset__" ]] || opt=(env "CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=$v")
    (cd "$PG_WORK/cwd" && printf '{"session_id":"s1"}' |
      "${opt[@]}" PATH="$PG_WORK/sysbin" CLAUDE_PLUGIN_DATA="$(mktemp -d "$PG_WORK/data.XXXXXX")" \
        "$NODE_BIN" "${PG_ARGS[@]}" 2>&1)
  }

  OUT_PG=$(run_probe false)
  RC_PG=$?
  if [[ $RC_PG -eq 0 && -z "$OUT_PG" ]]; then
    ok "probe-gate: bash_format_enabled=false -> exit 0 and no notice"
  else
    fail "probe-gate: bash_format_enabled=false should print nothing and exit 0 (rc=$RC_PG out=$OUT_PG)"
  fi
  for v in __unset__ true; do
    label="bash_format_enabled=$v"
    [[ "$v" == "__unset__" ]] && label="bash_format_enabled unset"
    OUT_PG=$(run_probe "$v")
    RC_PG=$?
    pg_ok=1
    while IFS=$'\t' read -r PG_NAME PG_CHECK PG_INSTALL; do
      [[ "$OUT_PG" == *"$PG_NAME"* && "$OUT_PG" == *"$PG_CHECK"* && "$OUT_PG" == *"$PG_INSTALL"* ]] || pg_ok=0
    done < <(jq -r '.requires[] | select(.id != "node") | [.id, .check, (.install | to_entries[0].value)] | @tsv' "$MANIFEST")
    if [[ $RC_PG -eq 0 && $pg_ok -eq 1 ]]; then
      ok "probe-gate: $label -> notices name each tool, its check and the install line"
    else
      fail "probe-gate: $label should print a missing-tool notice per tool (rc=$RC_PG out=$OUT_PG)"
    fi
  done
  rm -rf "${PG_WORK:?}"
fi

if ! command -v shfmt >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: shfmt or jq not on PATH -- remaining bash-format hook tests skipped"
  echo "PASS=$PASS FAIL=$FAIL"
  ((FAIL == 0)) || exit 1
  exit 0
fi

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
trap 'rm -rf "$WORK" "$UNRELATED"' EXIT

# The row's args from hooks.json, with the plugin root substituted.
mapfile -t ROW_ARGS < <(jq -r '.hooks.PostToolBatch[0].hooks[0].args[]' "$HOOKS_JSON" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$PLUGIN_ROOT#g")

SHEBANG='#!/usr/bin/env bash'
TABBED="$SHEBANG"$'\nif true; then\n\techo hi\nfi'
SPACED="$SHEBANG"$'\nif true; then\n  echo hi\nfi'
EC=$'[*.sh]\nindent_style = space\nindent_size = 2'

# new_repo <dir> [.editorconfig body; NO_CONFIG for none]
new_repo() {
  local r="$1" cfg="${2:-$EC}"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
  if [[ "$cfg" != NO_CONFIG ]]; then
    printf '%s\n' "$cfg" >"$r/.editorconfig"
  fi
}

# payload <tool> <file>...: a PostToolBatch payload with one call per file.
payload() {
  local tool="$1"
  shift
  jq -n --arg t "$tool" '{session_id: "s", hook_event_name: "PostToolBatch", tool_calls: [$ARGS.positional[] | {tool_name: $t, tool_input: {file_path: .}, tool_use_id: "toolu_x", tool_response: "ok"}]}' --args "$@"
}

# fire <payload> [env...]: the registered row, from an unrelated cwd. CLAUDE_PROJECT_DIR
# stays unset so scoping falls to git-working-tree membership.
fire() {
  local p="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true "$@" node "${ROW_ARGS[@]}" <<<"$p" 2>&1
  )
}

run_edit() { fire "$(payload Edit "$1")"; }

# --- Opt-in gate: an .editorconfig section naming shell files ----------------
REPO_NO="$WORK/no-config"
new_repo "$REPO_NO" NO_CONFIG
printf '%s\n' "$TABBED" >"$REPO_NO/a.sh"
OUT=$(run_edit "$REPO_NO/a.sh")
expect "no .editorconfig: exit 0 and silent" "0|" "$?|$OUT"
expect "no .editorconfig: file left untouched" "$TABBED" "$(cat "$REPO_NO/a.sh")"

REPO_STAR="$WORK/bare-star"
new_repo "$REPO_STAR" $'[*]\nindent_style = space\nend_of_line = lf'
printf '%s\n' "$TABBED" >"$REPO_STAR/a.sh"
run_edit "$REPO_STAR/a.sh" >/dev/null
expect "a bare [*] section does not opt in" "$TABBED" "$(cat "$REPO_STAR/a.sh")"

REPO_PATHONLY="$WORK/path-only"
new_repo "$REPO_PATHONLY" $'[scripts/**]\nindent_style = space'
mkdir -p "$REPO_PATHONLY/scripts"
printf '%s\n' "$TABBED" >"$REPO_PATHONLY/scripts/a.sh"
run_edit "$REPO_PATHONLY/scripts/a.sh" >/dev/null
expect "a path-only section does not opt in" "$TABBED" "$(cat "$REPO_PATHONLY/scripts/a.sh")"

REPO_ROOTSTOP="$WORK/root-stop"
new_repo "$REPO_ROOTSTOP"
mkdir -p "$REPO_ROOTSTOP/pkg"
printf 'root = true\n\n[*.md]\nindent_size = 4\n' >"$REPO_ROOTSTOP/pkg/.editorconfig"
printf '%s\n' "$TABBED" >"$REPO_ROOTSTOP/pkg/a.sh"
run_edit "$REPO_ROOTSTOP/pkg/a.sh" >/dev/null
expect "a nested root = true config with no shell section ends the walk" "$TABBED" "$(cat "$REPO_ROOTSTOP/pkg/a.sh")"

REPO="$WORK/consumer"
new_repo "$REPO"
mkdir -p "$REPO/src"
printf '%s\n' "$TABBED" >"$REPO/src/a.sh"
OUT=$(run_edit "$REPO/src/a.sh")
RC=$?
expect "a [*.sh] section above a nested file opts it in: formatted" "$SPACED" "$(cat "$REPO/src/a.sh")"
expect "a rewrite prints nothing to the model or the user, exit 0" "0|" "$RC|$OUT"

printf '%s\n' "$SPACED" >"$REPO/clean.sh"
OUT=$(run_edit "$REPO/clean.sh")
expect "a clean file: silent exit 0 and unchanged" "0||$SPACED" "$?|$OUT|$(cat "$REPO/clean.sh")"

# Findings no longer reach the model: an unassigned variable is neither fixed nor reported.
printf '%s\necho "$undefined_var"\n' "$TABBED" >"$REPO/lint.sh"
OUT=$(run_edit "$REPO/lint.sh")
expect "a ShellCheck finding is not reported (no additionalContext, no systemMessage)" "0|" "$?|$OUT"
expect "the finding's file is still formatted" "$SPACED"$'\necho "$undefined_var"' "$(cat "$REPO/lint.sh")"

printf '%s\nif true; then\n' "$SHEBANG" >"$REPO/syntax.sh"
OUT=$(run_edit "$REPO/syntax.sh")
expect "a mid-edit syntax error is silent" "0|" "$?|$OUT"

# --- The batch ---------------------------------------------------------------
# One call, several files, all formatted; a Read, a non-shell file and a
# duplicate are not.
REPO_B="$WORK/batch"
new_repo "$REPO_B" $'[*.{sh,bash}]\nindent_style = space\nindent_size = 2'
printf '%s\n' "$TABBED" >"$REPO_B/b1.sh"
printf '%s\n' "$TABBED" >"$REPO_B/b2.bash"
printf '%s\n' "$TABBED" >"$REPO_B/b3.sh"
printf '%s\n' "$TABBED" >"$REPO_B/notes.txt"
BATCH="$(jq -n --arg d "$REPO_B" '{session_id: "s", hook_event_name: "PostToolBatch", tool_calls: [
  {tool_name: "Write", tool_input: {file_path: "\($d)/b1.sh"}, tool_use_id: "1", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b2.bash"}, tool_use_id: "2", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b1.sh"}, tool_use_id: "3", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/notes.txt"}, tool_use_id: "4", tool_response: "ok"},
  {tool_name: "Read", tool_input: {file_path: "\($d)/b3.sh"}, tool_use_id: "5", tool_response: "1\tif"},
  {tool_name: "Bash", tool_input: {command: "ls b3.sh"}, tool_use_id: "6", tool_response: "b3.sh"}]}')"
OUT=$(fire "$BATCH")
expect "a mixed batch prints nothing" "0|" "$?|$OUT"
expect "batch: a Write'd .sh is formatted" "$SPACED" "$(cat "$REPO_B/b1.sh")"
expect "batch: an Edit'd .bash is formatted" "$SPACED" "$(cat "$REPO_B/b2.bash")"
expect "batch: a Read'd .sh is never formatted" "$TABBED" "$(cat "$REPO_B/b3.sh")"
expect "batch: a non-shell file is untouched" "$TABBED" "$(cat "$REPO_B/notes.txt")"

printf '%s\nif true; then\n' "$SHEBANG" >"$REPO_B/bad.sh"
printf '%s\n' "$TABBED" >"$REPO_B/good.sh"
fire "$(payload Edit "$REPO_B/bad.sh" "$REPO_B/good.sh")" >/dev/null
expect "a syntax-error file does not stop another file in the batch" "$SPACED" "$(cat "$REPO_B/good.sh")"

printf '%s\n' "$TABBED" >"$REPO_B/multi.sh"
fire "$(payload MultiEdit "$REPO_B/multi.sh")" >/dev/null
expect "a MultiEdit'd file is formatted" "$SPACED" "$(cat "$REPO_B/multi.sh")"

# A file shfmt rewrites to a different array key is put back, silently.
REPO_SUB="$WORK/subscript"
new_repo "$REPO_SUB"
SUBSCRIPTED="$SHEBANG"$'\ndeclare -A m\nm[a-b]=1\necho "${m[a-b]}"'
printf '%s\n' "$SUBSCRIPTED" >"$REPO_SUB/s.sh"
OUT=$(run_edit "$REPO_SUB/s.sh")
expect "an array-subscript rewrite prints nothing, exit 0" "0|" "$?|$OUT"
expect "the subscript guard leaves the bytes as written" "$SUBSCRIPTED" "$(cat "$REPO_SUB/s.sh")"

# --- Skips -------------------------------------------------------------------
# .githooks/ holds installed copies of check scripts, never rewritten here.
mkdir -p "$REPO/.githooks/bash-format"
printf '%s\n' "$TABBED" >"$REPO/.githooks/bash-format/copy.sh"
fire "$(payload Write "$REPO/.githooks/bash-format/copy.sh")" >/dev/null
expect "a file under .githooks/ is skipped" "$TABBED" "$(cat "$REPO/.githooks/bash-format/copy.sh")"

# An ignore = true section holds for an explicitly passed path.
REPO_IGN="$WORK/ignore-section"
new_repo "$REPO_IGN" $'[*.sh]\nindent_style = space\nindent_size = 2\n\n[gen/*.sh]\nignore = true'
mkdir -p "$REPO_IGN/gen"
printf '%s\n' "$TABBED" >"$REPO_IGN/gen/g.sh"
OUT=$(run_edit "$REPO_IGN/gen/g.sh")
expect "an ignore = true section leaves the file untouched and silent" "0|$TABBED" "$?|$OUT$(cat "$REPO_IGN/gen/g.sh")"

# The kill switch.
printf '%s\n' "$TABBED" >"$REPO/kill.sh"
OUT=$(fire "$(payload Edit "$REPO/kill.sh")" CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=false)
expect "kill switch off: silent and the file untouched" "0|$TABBED" "$?|$OUT$(cat "$REPO/kill.sh")"

# shfmt absent: the file is skipped silently; the SessionStart probe reports the gap.
REPO_NF="$WORK/no-shfmt"
new_repo "$REPO_NF"
printf '%s\n' "$TABBED" >"$REPO_NF/app.sh"
FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink node; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
OUT=$(fire "$(payload Edit "$REPO_NF/app.sh")" PATH="$FAKEBIN")
expect "shfmt absent: silent exit 0 and the file untouched" "0|$TABBED" "$?|$OUT$(cat "$REPO_NF/app.sh")"

# Gitignored path: neither rewritten by default, unless bash_format_lint_gitignored is set.
REPO_GI="$WORK/gitignored"
new_repo "$REPO_GI"
git -C "$REPO_GI" config core.excludesFile /dev/null
printf '.work/\n' >"$REPO_GI/.gitignore"
mkdir -p "$REPO_GI/.work"
printf '%s\n' "$TABBED" >"$REPO_GI/.work/scratch.sh"
run_edit "$REPO_GI/.work/scratch.sh" >/dev/null
expect "gitignored: file not rewritten" "$TABBED" "$(cat "$REPO_GI/.work/scratch.sh")"
fire "$(payload Edit "$REPO_GI/.work/scratch.sh")" CLAUDE_PLUGIN_OPTION_BASH_FORMAT_LINT_GITIGNORED=true >/dev/null
expect "gitignored + bash_format_lint_gitignored=true: file formatted" "$SPACED" "$(cat "$REPO_GI/.work/scratch.sh")"

# Symlinked repo root: the file reached through a symlinked directory is still formatted.
if ln -s "$WORK/symlink-real" "$WORK/symlink-link" 2>/dev/null; then
  REPO_SL="$WORK/symlink-real"
  new_repo "$REPO_SL"
  mkdir -p "$REPO_SL/pkg"
  printf '%s\n' "$TABBED" >"$REPO_SL/pkg/mod.sh"
  run_edit "$WORK/symlink-link/pkg/mod.sh" >/dev/null
  expect "symlinked root: the file is formatted" "$SPACED" "$(cat "$REPO_SL/pkg/mod.sh")"
else
  echo "SKIP: symlinks unavailable on this filesystem -- symlinked-root case skipped"
fi

# --- shfmt < 3.8: --apply-ignore fallback (capability probe) ------------------
# The format pass probes `shfmt --apply-ignore --version`, then formats with the
# flag on success. Older shfmt rejects the flag on the probe, so the plain -w
# compatibility path must still format. The stubs sit first on PATH.
STUBDIR="$(mktemp -d "$WORK/shfmtstub.XXXXXX")"
cat >"$STUBDIR/shfmt" <<'STUB'
#!/usr/bin/env bash
# Simulate shfmt < 3.8: --apply-ignore is an unknown flag -> the Go flag
# parser's rejection text (verified against real shfmt), then fail, no format.
for a in "$@"; do
  if [[ "$a" == "--apply-ignore" ]]; then
    echo "flag provided but not defined: -apply-ignore" >&2
    exit 2
  fi
done
# Plain `-w FILE`: rewrite the (last-arg) file to a formatted shape so the
# caller's fallback branch is observable.
f="${*: -1}"
printf '#!/usr/bin/env bash\nif true; then\n  echo hi\nfi\n' >"$f"
STUB
chmod +x "$STUBDIR/shfmt"
REPO_OLD="$WORK/old-shfmt"
new_repo "$REPO_OLD"
printf '%s\n' "$TABBED" >"$REPO_OLD/x.sh"
fire "$(payload Edit "$REPO_OLD/x.sh")" PATH="$STUBDIR:$PATH" >/dev/null
expect "shfmt<3.8 (--apply-ignore rejected) -> plain -w fallback still formats" "$SPACED" "$(cat "$REPO_OLD/x.sh")"

# A shfmt that KNOWS --apply-ignore but whose format run fails must NOT be re-run
# without the flag: that discarded the repo's `ignore = true` opt-out and
# re-tabbed a file the consumer asked shfmt to leave alone. The stub answers the
# probe successfully and fails only the -w run, so it separates "no such flag"
# from "this run failed".
STUBDIR2="$(mktemp -d "$WORK/shfmtstub2.XXXXXX")"
cat >"$STUBDIR2/shfmt" <<'STUB2'
#!/usr/bin/env bash
has_ignore=0 has_version=0
for a in "$@"; do
  [[ "$a" == "--apply-ignore" ]] && has_ignore=1
  [[ "$a" == "--version" ]] && has_version=1
done
# Capability probe: the flag exists on this shfmt.
if ((has_ignore && has_version)); then
  echo v3.13.1
  exit 0
fi
# Format run with the flag: fail transiently, formatting nothing.
((has_ignore)) && exit 1
# Plain `-w FILE`: rewrite the file, so a wrong fallback is observable.
f="${*: -1}"
printf '#!/usr/bin/env bash\nif true; then\n\techo hi\nfi\n' >"$f"
STUB2
chmod +x "$STUBDIR2/shfmt"
REPO_TRANSIENT="$WORK/apply-ignore-transient"
new_repo "$REPO_TRANSIENT"
printf '%s\n' "$SPACED" >"$REPO_TRANSIENT/x.sh"
cp "$REPO_TRANSIENT/x.sh" "$WORK/apply-ignore-transient.expected"
fire "$(payload Edit "$REPO_TRANSIENT/x.sh")" PATH="$STUBDIR2:$PATH" >/dev/null
if cmp -s "$REPO_TRANSIENT/x.sh" "$WORK/apply-ignore-transient.expected"; then
  ok "failed --apply-ignore run does not re-format without the flag"
else
  fail "opt-out discarded by fallback: $(cat "$REPO_TRANSIENT/x.sh")"
fi

# An UNCLASSIFIED probe failure must not take the plain-format path either: a
# wrapper that flakes on its first invocation says nothing about the flag.
STUBDIR3="$(mktemp -d "$WORK/shfmtstub3.XXXXXX")"
cat >"$STUBDIR3/shfmt" <<'STUB3'
#!/usr/bin/env bash
for a in "$@"; do
  if [[ "$a" == "--apply-ignore" ]]; then
    echo "shfmt-wrapper: transient startup failure" >&2
    exit 1
  fi
done
f="${*: -1}"
printf '#!/usr/bin/env bash\nif true; then\n\techo hi\nfi\n' >"$f"
STUB3
chmod +x "$STUBDIR3/shfmt"
REPO_FLAKE="$WORK/probe-flake"
new_repo "$REPO_FLAKE"
printf '%s\n' "$SPACED" >"$REPO_FLAKE/x.sh"
cp "$REPO_FLAKE/x.sh" "$WORK/probe-flake.expected"
OUT=$(fire "$(payload Edit "$REPO_FLAKE/x.sh")" PATH="$STUBDIR3:$PATH")
if cmp -s "$REPO_FLAKE/x.sh" "$WORK/probe-flake.expected"; then
  ok "unclassified probe failure -> file untouched (no plain -w fallback)"
else
  fail "unclassified probe failure mutated the file: $(cat "$REPO_FLAKE/x.sh")"
fi
expect "unclassified probe failure prints nothing from the batch row" "" "$OUT"

# --- Spawn budget ------------------------------------------------------------
# PostToolBatch has no matcher, so the row fires on every batch of every session.
# A batch that holds no string ending in "sh" costs only the node launcher.
CENSUS="$REPO_ROOT/scripts/hook-census.sh"
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1; then
  out="$(bash "$CENSUS" bash-format PostToolBatch bash-format.sh \
    '{"session_id":"census","hook_event_name":"PostToolBatch","cwd":"@DIR@","tool_calls":[{"tool_name":"Read","tool_input":{"file_path":"@DIR@/README.md"},"tool_use_id":"toolu_census","tool_response":"# readme"}]}' \
    --check 'test ! -s "$HOOK_STDOUT"')"
  expect "spawn budget: a batch with no shell file costs only the node launcher" "spawns=1" "${out%% *}"
else
  echo "NOTE: strace or scripts/hook-census.sh absent; the spawn budget case did not run."
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
