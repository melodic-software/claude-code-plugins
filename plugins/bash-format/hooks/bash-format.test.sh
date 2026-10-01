#!/usr/bin/env bash
# Black-box contract test for bash-format.sh (the bash-format plugin hook).
#
# Proves WIRING: the hook fires on *.sh/*.bash, skips otherwise, surfaces
# ShellCheck findings via additionalContext (advisory, exit 0), honors the
# kill switch, gates shfmt formatting on a consumer .editorconfig (present ->
# format, absent -> leave bytes untouched), and emits a schema-valid telemetry
# envelope. No medley-policy prose in the surfaced context.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# The hook is invoked as a subprocess from an UNRELATED cwd so any reliance on
# the caller's working directory would surface (the tools are file-anchored, so
# a correct hook needs no cd). shellcheck is required; without it the lint
# branch -- which drives the findings assertions -- cannot fire, so the suite
# skips. shfmt-gated cases skip when shfmt is absent.

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/bash-format.sh"

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

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "SKIP: shellcheck not on PATH -- bash-format hook tests skipped"
  exit 0
fi
HAVE_SHFMT=0
if command -v shfmt >/dev/null 2>&1; then
  HAVE_SHFMT=1
fi

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

# shellcheck source=hook-test-sink.sh
source "$HOOK_DIR/hook-test-sink.sh"

new_repo() {
  local r="$1"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
}

# Invoke the hook from an unrelated cwd with caller-supplied env
# (NAME=VALUE ...), which may override CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED.
# CLAUDE_PROJECT_DIR is left UNSET so read_file_path's membership guard is
# disabled (not part of the fire gate); this isolates lint/format behavior from
# path-form mismatch in the guard.
run_hook_env() {
  local file_path="$1" payload
  shift
  # A here-string, never a pipe: the kill switch exits before reading stdin, and
  # a printf still writing then fails on the closed pipe, which pipefail reports.
  printf -v payload '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path"
  (
    cd "$UNRELATED" || return 1
    env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOK" <<<"$payload"
  )
}

run_hook() {
  run_hook_env "$1" CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true
}

REPO="$WORK/consumer"
new_repo "$REPO"

# --- Case 1: clean .sh -> exit 0, empty stdout ------------------------------
cat >"$REPO/clean.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "clean"
EOF
OUT=$(run_hook "$REPO/clean.sh")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean .sh -> exit 0"; else fail "clean .sh exit $RC"; fi
if [[ -z "$OUT" ]]; then ok "clean .sh -> empty stdout"; else fail "clean .sh stdout not empty: $OUT"; fi

# --- Case 2: clean .bash -> exit 0 (glob match) -----------------------------
cat >"$REPO/clean.bash" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "clean bash"
EOF
OUT=$(run_hook "$REPO/clean.bash")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean .bash -> exit 0 (glob match)"; else fail "clean .bash exit $RC"; fi

# --- Case 3: SC2154 reference to unassigned var -> advisory (exit 0) ---------
cat >"$REPO/violation.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$undefined_var"
EOF
OUT=$(run_hook "$REPO/violation.sh")
RC=$?
if [[ $RC -eq 0 ]]; then ok "SC2154 violation -> exit 0 (advisory)"; else fail "violation exit $RC (must be advisory)"; fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -q 'SC2154'; then
    ok "violation -> SC2154 in additionalContext"
  else
    fail "violation ctx missing SC2154: $CTX"
  fi
  if printf '%s' "$CTX" | grep -qi 'commit/CI will block\|hard gate\|lefthook'; then
    fail "ctx still carries medley-policy prose: $CTX"
  else
    ok "ctx free of medley-policy prose"
  fi
else
  fail "violation -> no additionalContext JSON: $OUT"
fi

# --- Case 4: non-shell extension -> exit 0 silently -------------------------
echo "not a script" >"$REPO/foo.txt"
OUT=$(run_hook "$REPO/foo.txt")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "non-shell ext -> exit 0 silent"; else fail "non-shell not skipped (rc=$RC out=$OUT)"; fi

# --- Case 5: kill switch bypasses hook --------------------------------------
OUT=$(run_hook_env "$REPO/violation.sh" CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=false)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch off -> exit 0 silent despite violation"; else fail "kill switch failed (rc=$RC out=$OUT)"; fi

# --- Case 6+7: shfmt gate on .editorconfig ----------------------------------
# Fixture body is deliberately unindented inside an if-block; shfmt would indent
# the inner line. Gate ON (with .editorconfig) -> indented; gate OFF -> untouched.
if [[ $HAVE_SHFMT -eq 1 ]]; then
  # Gate ON: .editorconfig at repo root, file in a subdir (exercises the walk).
  REPO_YES="$WORK/with-config"
  new_repo "$REPO_YES"
  cat >"$REPO_YES/.editorconfig" <<'EOF'
root = true
[*.sh]
indent_style = space
indent_size = 2
EOF
  mkdir -p "$REPO_YES/src"
  printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_YES/src/fmt.sh"
  OUT=$(run_hook "$REPO_YES/src/fmt.sh")
  if grep -q '^  echo hi$' "$REPO_YES/src/fmt.sh"; then
    ok "shfmt gate ON (.editorconfig present) -> file formatted"
  else
    fail "shfmt gate ON -> not formatted: $(cat "$REPO_YES/src/fmt.sh")"
  fi
  if printf '%s' "$OUT" | grep -q 'bash-format: reformatted'; then
    ok "shfmt gate ON -> user-channel mutation disclosure"
  else
    fail "shfmt gate ON -> missing systemMessage disclosure: $OUT"
  fi

  # Rewrite AND findings -> ONE JSON document, both channels (#3406). The
  # unindented if-block makes shfmt rewrite; the unassigned-var reference makes
  # ShellCheck report SC2154. Disclosure and findings must compose into a
  # single document — a second printed object is an invalid hook response and
  # either message can be lost.
  # shellcheck disable=SC2016  # $undefined_variable must stay literal in the emitted fixture (it is what makes ShellCheck report SC2154)
  printf '#!/usr/bin/env bash\nif true; then\necho "$undefined_variable"\nfi\n' >"$REPO_YES/src/both.sh"
  OUT=$(run_hook "$REPO_YES/src/both.sh")
  DOCS=$(printf '%s' "$OUT" | jq -s 'length' 2>/dev/null)
  if [[ "$DOCS" == "1" ]]; then
    ok "rewrite+findings -> exactly one JSON document (#3406)"
  else
    fail "rewrite+findings -> $DOCS documents on stdout (#3406): $OUT"
  fi
  if printf '%s' "$OUT" | jq -e '.systemMessage' >/dev/null 2>&1 &&
    printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
    MSG=$(printf '%s' "$OUT" | jq -r '.systemMessage')
    if printf '%s' "$CTX" | grep -q 'SC2154' && printf '%s' "$MSG" | grep -qi 'reformatted'; then
      ok "rewrite+findings -> both channels carried in the one document"
    else
      fail "rewrite+findings -> channels malformed (ctx=$CTX msg=$MSG)"
    fi
  else
    fail "rewrite+findings -> a channel is missing: $OUT"
  fi

  # Gate OFF: no .editorconfig anywhere in the repo -> bytes untouched.
  REPO_NO="$WORK/no-config"
  new_repo "$REPO_NO"
  mkdir -p "$REPO_NO/src"
  printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_NO/src/fmt.sh"
  run_hook "$REPO_NO/src/fmt.sh" >/dev/null
  if grep -q '^echo hi$' "$REPO_NO/src/fmt.sh"; then
    ok "shfmt gate OFF (no .editorconfig) -> file left untouched"
  else
    fail "shfmt gate OFF -> file was reformatted: $(cat "$REPO_NO/src/fmt.sh")"
  fi

  # editorconfig opt-OUT: an `ignore = true` section for the edited file must be
  # honored even on this direct-file invocation (requires --apply-ignore; shfmt
  # skips ignore rules for direct files without it). The file is misformatted and
  # an .editorconfig IS present (so the gate passes), but the ignore rule must
  # leave it untouched.
  REPO_IGN="$WORK/ignore-config"
  new_repo "$REPO_IGN"
  cat >"$REPO_IGN/.editorconfig" <<'EOF'
root = true
[*.sh]
indent_style = space
indent_size = 2
[gen.sh]
ignore = true
EOF
  printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_IGN/gen.sh"
  run_hook "$REPO_IGN/gen.sh" >/dev/null
  if grep -q '^echo hi$' "$REPO_IGN/gen.sh"; then
    ok "shfmt honors editorconfig ignore=true (--apply-ignore) -> file untouched"
  else
    fail "shfmt ignored editorconfig ignore=true -> file was reformatted: $(cat "$REPO_IGN/gen.sh")"
  fi

  # Opt-in precision: an .editorconfig with NO shell-applicable section (only
  # [*.md], or a bare [*]) must NOT trigger formatting — otherwise shfmt would
  # impose its built-in defaults on shell files the repo never opted in for.
  REPO_NONSHELL="$WORK/nonshell-config"
  new_repo "$REPO_NONSHELL"
  printf '[*.md]\nindent_style = space\n' >"$REPO_NONSHELL/.editorconfig"
  printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_NONSHELL/x.sh"
  run_hook "$REPO_NONSHELL/x.sh" >/dev/null
  if grep -q '^echo hi$' "$REPO_NONSHELL/x.sh"; then
    ok "non-shell .editorconfig ([*.md] only) -> shell file left untouched"
  else
    fail "non-shell .editorconfig -> shell file was reformatted: $(cat "$REPO_NONSHELL/x.sh")"
  fi

  # A bare [*] catch-all is NOT a shell opt-in (#1817): most repos set only
  # line-ending / charset properties there, and treating [*] as opt-in rewrote
  # shell files to shfmt defaults. Even when [*] carries indent_* properties,
  # opt-in requires an explicit shell glob (`[*.sh]`, etc.).
  REPO_STAR="$WORK/star-config"
  new_repo "$REPO_STAR"
  printf 'root = true\n[*]\nindent_style = space\nindent_size = 2\n' >"$REPO_STAR/.editorconfig"
  printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_STAR/x.sh"
  run_hook "$REPO_STAR/x.sh" >/dev/null
  if grep -q '^echo hi$' "$REPO_STAR/x.sh"; then
    ok "bare [*] .editorconfig -> shell file left untouched"
  else
    fail "bare [*] treated as shell opt-in: $(cat "$REPO_STAR/x.sh")"
  fi

  # Control: a generic [*] with only line-ending properties (the common case
  # that #1817 observed) must also leave the file untouched.
  REPO_STAR_EOL="$WORK/star-eol-config"
  new_repo "$REPO_STAR_EOL"
  printf 'root = true\n[*]\nend_of_line = lf\ninsert_final_newline = true\n' >"$REPO_STAR_EOL/.editorconfig"
  printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_STAR_EOL/x.sh"
  run_hook "$REPO_STAR_EOL/x.sh" >/dev/null
  if grep -q '^echo hi$' "$REPO_STAR_EOL/x.sh"; then
    ok "bare [*] with only eol props -> shell file left untouched"
  else
    fail "bare [*] eol-only treated as shell opt-in: $(cat "$REPO_STAR_EOL/x.sh")"
  fi

  # A brace-list section naming sh (`[*.{sh,bash}]`) governs shell files:
  # section_applies_to_shell matches the `{,sh,}` / `{sh,` / `,sh}` shapes, so
  # formatting opts in. Regression guard for the documented brace-list form.
  REPO_BRACE="$WORK/brace-config"
  new_repo "$REPO_BRACE"
  printf 'root = true\n[*.{sh,bash}]\nindent_style = space\nindent_size = 2\n' >"$REPO_BRACE/.editorconfig"
  printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_BRACE/x.sh"
  run_hook "$REPO_BRACE/x.sh" >/dev/null
  if grep -q '^  echo hi$' "$REPO_BRACE/x.sh"; then
    ok "[*.{sh,bash}] brace-list .editorconfig -> shell file formatted"
  else
    fail "[*.{sh,bash}] brace-list -> shell file not formatted: $(cat "$REPO_BRACE/x.sh")"
  fi

  # A path-prefixed shell glob (`[**/*.sh]`) governs shell files:
  # section_applies_to_shell keys on the `*.sh` suffix regardless of a leading
  # path component. Regression guard for the documented path-prefixed form.
  REPO_PATHGLOB="$WORK/pathglob-config"
  new_repo "$REPO_PATHGLOB"
  printf 'root = true\n[**/*.sh]\nindent_style = space\nindent_size = 2\n' >"$REPO_PATHGLOB/.editorconfig"
  mkdir -p "$REPO_PATHGLOB/src"
  printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_PATHGLOB/src/x.sh"
  run_hook "$REPO_PATHGLOB/src/x.sh" >/dev/null
  if grep -q '^  echo hi$' "$REPO_PATHGLOB/src/x.sh"; then
    ok "[**/*.sh] path-prefixed .editorconfig -> shell file formatted"
  else
    fail "[**/*.sh] path-prefixed -> shell file not formatted: $(cat "$REPO_PATHGLOB/src/x.sh")"
  fi
else
  echo "  (shfmt absent -- gate cases skipped)"
fi

# --- shfmt < 3.8 --apply-ignore fallback (capability probe) -----------------
# The format pass probes `shfmt --apply-ignore --version`, then formats with
# the flag on success. Older shfmt rejects the flag on the probe, so the
# plain-`-w` compatibility path must still format. A stub shfmt that REJECTS
# --apply-ignore (simulating < 3.8) but formats on plain -w proves that path
# runs. Independent of the host's real shfmt: the stub is prepended to PATH.
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
# Plain `-w FILE` path: rewrite the (last-arg) file to a formatted shape so the
# caller's fallback branch is observable.
f="${*: -1}"
printf '#!/usr/bin/env bash\nif true; then\n  echo hi\nfi\n' >"$f"
STUB
chmod +x "$STUBDIR/shfmt"
REPO_OLDSHFMT="$WORK/old-shfmt"
new_repo "$REPO_OLDSHFMT"
printf 'root = true\n[*.sh]\nindent_style = space\nindent_size = 2\n' >"$REPO_OLDSHFMT/.editorconfig"
printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_OLDSHFMT/x.sh"
(
  cd "$UNRELATED" || exit 1
  printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_OLDSHFMT/x.sh" |
    env -u CLAUDE_PROJECT_DIR PATH="$STUBDIR:$PATH" \
      CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true bash "$HOOK" >/dev/null
)
if grep -q '^  echo hi$' "$REPO_OLDSHFMT/x.sh"; then
  ok "shfmt<3.8 (--apply-ignore rejected) -> plain -w fallback still formats"
else
  fail "shfmt<3.8 fallback did not format: $(cat "$REPO_OLDSHFMT/x.sh")"
fi

# A shfmt that KNOWS --apply-ignore but whose format run fails must NOT be
# re-run without the flag. Doing so discarded the repo's `ignore = true` opt-out
# and re-tabbed a file the consumer asked shfmt to leave alone (#1817). The
# stub answers the capability probe successfully and fails only the -w run, so
# it separates "no such flag" from "this run failed" — the distinction the old
# `--apply-ignore -w || -w` could not make.
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
printf 'root = true\n[*.sh]\nignore = true\n' >"$REPO_TRANSIENT/.editorconfig"
printf '#!/usr/bin/env bash\nif true; then\n  echo hi\nfi\n' >"$REPO_TRANSIENT/x.sh"
# Byte-for-byte reference: `$(cat)` strips trailing newlines, so a string
# compare would report a difference the file does not have.
cp "$REPO_TRANSIENT/x.sh" "$WORK/apply-ignore-transient.expected"
(
  cd "$UNRELATED" || exit 1
  printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_TRANSIENT/x.sh" |
    env -u CLAUDE_PROJECT_DIR PATH="$STUBDIR2:$PATH" \
      CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true bash "$HOOK" >/dev/null
)
if cmp -s "$REPO_TRANSIENT/x.sh" "$WORK/apply-ignore-transient.expected"; then
  ok "failed --apply-ignore run does not re-format without the flag"
else
  fail "opt-out discarded by fallback: $(cat "$REPO_TRANSIENT/x.sh")"
fi

# An UNCLASSIFIED probe failure must not take the plain-format path either. A
# wrapper that flakes on its first invocation fails the probe without saying
# anything about the flag; treating that as "old shfmt" would mutate through
# the same discarded opt-out. Only a confirmed unsupported-flag rejection may
# fall back — anything else leaves the file untouched and says so.
STUBDIR3="$(mktemp -d "$WORK/shfmtstub3.XXXXXX")"
cat >"$STUBDIR3/shfmt" <<'STUB3'
#!/usr/bin/env bash
for a in "$@"; do
  if [[ "$a" == "--apply-ignore" ]]; then
    echo "shfmt-wrapper: transient startup failure" >&2
    exit 1
  fi
done
# Plain `-w FILE`: rewrite the file, so a wrong compatibility fallback is
# observable.
f="${*: -1}"
printf '#!/usr/bin/env bash\nif true; then\n\techo hi\nfi\n' >"$f"
STUB3
chmod +x "$STUBDIR3/shfmt"
REPO_FLAKE="$WORK/probe-flake"
new_repo "$REPO_FLAKE"
printf 'root = true\n[*.sh]\nignore = true\n' >"$REPO_FLAKE/.editorconfig"
printf '#!/usr/bin/env bash\nif true; then\n  echo hi\nfi\n' >"$REPO_FLAKE/x.sh"
cp "$REPO_FLAKE/x.sh" "$WORK/probe-flake.expected"
FLAKE_OUT="$(
  cd "$UNRELATED" || exit 1
  printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_FLAKE/x.sh" |
    env -u CLAUDE_PROJECT_DIR PATH="$STUBDIR3:$PATH" \
      CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true bash "$HOOK"
)"
if cmp -s "$REPO_FLAKE/x.sh" "$WORK/probe-flake.expected"; then
  ok "unclassified probe failure -> file untouched (no plain -w fallback)"
else
  fail "unclassified probe failure mutated the file: $(cat "$REPO_FLAKE/x.sh")"
fi
if [[ "$FLAKE_OUT" == *"capability probe failed unexpectedly"* ]]; then
  ok "unclassified probe failure is said out loud, not a silent skip"
else
  fail "unclassified probe failure skipped silently: $FLAKE_OUT"
fi

# --- openBinaryFile / missing-file race (#1817) ------------------------------
# ShellCheck's GHC runtime reports `openBinaryFile: does not exist` when the
# path is gone by the time it opens the file. That must never become a
# findings line. Drive the hook with a stub shellcheck that always emits the
# error text; the hook must exit 0 with empty findings/context for it.
STUBSC="$(mktemp -d "$WORK/scstub.XXXXXX")"
cat >"$STUBSC/shellcheck" <<'STUBSC'
#!/usr/bin/env bash
f="${*: -1}"
echo "$f: $f: openBinaryFile: does not exist (No such file or directory)" >&2
exit 1
STUBSC
chmod +x "$STUBSC/shellcheck"
# Keep real shfmt off the path so only the lint pass runs.
REPO_OBF="$WORK/openbinary"
new_repo "$REPO_OBF"
printf '#!/usr/bin/env bash\necho hi\n' >"$REPO_OBF/x.sh"
OBF_OUT="$(
  cd "$UNRELATED" || exit 1
  printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_OBF/x.sh" |
    env -u CLAUDE_PROJECT_DIR PATH="$STUBSC:/usr/bin:/bin" \
      CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true bash "$HOOK"
)"
RC_OBF=$?
if [[ $RC_OBF -eq 0 && "$OBF_OUT" != *openBinaryFile* ]]; then
  ok "openBinaryFile from shellcheck is not surfaced as a finding"
else
  fail "openBinaryFile leaked (rc=$RC_OBF out=$OBF_OUT)"
fi

# Windows/MSYS path form: when cygpath can produce a mixed long path for an
# existing file, the hook must still lint cleanly (no openBinaryFile) — the
# TOOL_FILE normalization path under test.
if command -v cygpath >/dev/null 2>&1 && command -v shellcheck >/dev/null 2>&1; then
  REPO_WIN="$WORK/winpath"
  new_repo "$REPO_WIN"
  printf '#!/usr/bin/env bash\necho hi\n' >"$REPO_WIN/x.sh"
  WIN_PATH="$(cygpath -w "$REPO_WIN/x.sh")"
  # JSON needs escaped backslashes.
  WIN_JSON="${WIN_PATH//\\/\\\\}"
  WIN_OUT="$(
    cd "$UNRELATED" || exit 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$WIN_JSON" |
      env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true bash "$HOOK"
  )"
  RC_WIN=$?
  if [[ $RC_WIN -eq 0 && "$WIN_OUT" != *openBinaryFile* ]]; then
    ok "Windows Win32 path form -> hook runs without openBinaryFile"
  else
    fail "Windows path form failed (rc=$RC_WIN out=$WIN_OUT)"
  fi
else
  echo "  (cygpath/shellcheck absent -- Windows path form case skipped)"
fi

# ============================================================================
# Telemetry
# ============================================================================

# --- Sink unset -> empty stdout, exit 0 (parity) ----------------------------
OUT_NS=$(run_hook_env "$REPO/clean.sh" -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true)
RC_NS=$?
if [[ $RC_NS -eq 0 && -z "$OUT_NS" ]]; then
  ok "telemetry/sink-unset: exit 0, empty stdout (parity)"
else
  fail "telemetry/sink-unset: rc=$RC_NS out=$OUT_NS"
fi

# --- Stub sink + violation -> envelope status ok with findings --------------
TEL="$(mktemp)"
SINK="$(make_sink "cat >\"$TEL\"")"
run_hook_env "$REPO/violation.sh" CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINK" >/dev/null
wait_for_sink "$TEL"
if [[ -s "$TEL" ]]; then
  ok "telemetry/stub-sink: envelope received"
  if check_envelope "$TEL"; then ok "envelope: matches envelope schema"; else fail "envelope: does not match envelope schema. envelope=$(cat "$TEL")"; fi
  if [[ "$(jq -r '.hook' "$TEL")" == "bash-format" ]]; then ok "envelope: hook is bash-format"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "envelope: status ok"; else fail "envelope: status=$(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.1" ]]; then ok "envelope: schema_version 1.1"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq '.data.findings | length' "$TEL")" -ge 1 ]]; then ok "envelope: findings populated"; else fail "envelope: findings empty ($(jq '.data.findings' "$TEL"))"; fi
  if jq -e '.data.findings | any(test("SC2154"))' "$TEL" >/dev/null 2>&1; then ok "envelope: findings name SC2154"; else fail "envelope: findings missing SC2154 ($(jq '.data.findings' "$TEL"))"; fi
  # No .editorconfig opt-in in this repo, so shfmt never ran: the hook did not rewrite the file.
  if [[ "$(jq -r '.data.changed' "$TEL")" == "false" ]]; then ok "envelope: data.changed false (shfmt gate off, nothing rewritten)"; else fail "envelope: data.changed=$(jq -c '.data.changed' "$TEL")"; fi
  FREL=$(jq -r '.data.file' "$TEL")
  if [[ -n "$FREL" && "$FREL" != /* && "$FREL" != ?:* ]]; then ok "envelope: data.file repo-relative ($FREL)"; else fail "envelope: data.file not repo-relative: $FREL"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "envelope: duration_ms non-negative int"; else fail "envelope: duration_ms invalid ($(jq .duration_ms "$TEL"))"; fi
else
  fail "telemetry/stub-sink: no envelope written"
fi
rm -f "$TEL"

# --- Stub sink + clean file -> status ok, findings [] -----------------------
TELC="$(mktemp)"
SINKC="$(make_sink "cat >\"$TELC\"")"
run_hook_env "$REPO/clean.sh" CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKC" >/dev/null
wait_for_sink "$TELC"
if [[ -s "$TELC" ]]; then
  if [[ "$(jq -r '.status' "$TELC")" == "ok" ]]; then ok "telemetry/clean: status ok"; else fail "telemetry/clean: status=$(jq -r '.status' "$TELC")"; fi
  if [[ "$(jq '.data.findings | length' "$TELC")" -eq 0 ]]; then ok "telemetry/clean: findings empty array"; else fail "telemetry/clean: findings not empty ($(jq '.data.findings' "$TELC"))"; fi
else
  fail "telemetry/clean: no envelope written"
fi
rm -f "$TELC"

# --- Stub sink + shfmt rewrite -> data.changed true (#3755) -------------------
if [[ $HAVE_SHFMT -eq 1 ]]; then
  printf '#!/usr/bin/env bash\nif true; then\necho tel\nfi\n' >"$REPO_YES/src/tel-fmt.sh"
  TELF="$(mktemp)"
  SINKF="$(make_sink "cat >\"$TELF\"")"
  run_hook_env "$REPO_YES/src/tel-fmt.sh" CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKF" >/dev/null
  wait_for_sink "$TELF"
  if [[ -s "$TELF" ]]; then
    if [[ "$(jq -r '.data.changed' "$TELF")" == "true" ]]; then ok "telemetry/rewrite: data.changed true after shfmt reindented the file"; else fail "telemetry/rewrite: data.changed=$(jq -c '.data.changed' "$TELF")"; fi
  else
    fail "telemetry/rewrite: no envelope written"
  fi
  rm -f "$TELF"
  # The same file again is already formatted: shfmt ran and changed no bytes.
  TELF2="$(mktemp)"
  SINKF2="$(make_sink "cat >\"$TELF2\"")"
  run_hook_env "$REPO_YES/src/tel-fmt.sh" CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKF2" >/dev/null
  wait_for_sink "$TELF2"
  if [[ -s "$TELF2" ]]; then
    if [[ "$(jq -r '.data.changed' "$TELF2")" == "false" ]]; then ok "telemetry/rewrite: data.changed false when shfmt ran and changed nothing"; else fail "telemetry/rewrite: second run data.changed=$(jq -c '.data.changed' "$TELF2")"; fi
  else
    fail "telemetry/rewrite: no envelope written on the second run"
  fi
  rm -f "$TELF2"
fi

# --- Missing-tool visibility (dim-9 doctrine) --------------------------------
# Fake-bin dir of exec wrappers so individual tools can be removed from PATH
# without losing the coreutils the hook and the notice dedup need.
FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink shellcheck shfmt; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done

# ShellCheck absent -> visible once-per-session notice on both channels.
rm -f "$FAKEBIN/shellcheck" "$FAKEBIN/shfmt"
SC_DATA="$(mktemp -d "$WORK/plugdata.XXXXXX")"
run_no_tools() {
  (
    cd "$UNRELATED" || return 1
    printf '{"session_id":"test-sc-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$1" |
      env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$SC_DATA" \
        CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true bash "$HOOK"
  )
}
OUT_SC=$(run_no_tools "$REPO/clean.sh")
RC_SC=$?
if [[ $RC_SC -eq 0 ]]; then ok "shellcheck-absent -> exit 0"; else fail "shellcheck-absent exit $RC_SC"; fi
if jq -e '(.systemMessage | contains("shellcheck")) and (.hookSpecificOutput.additionalContext | contains("shellcheck"))' <<<"$OUT_SC" >/dev/null 2>&1; then
  ok "shellcheck-absent -> visible notice on both channels"
else
  fail "shellcheck-absent: notice missing or malformed: $OUT_SC"
fi
if jq -e '
  (.hookSpecificOutput.additionalContext | contains("PATH probed:")) and
  (.hookSpecificOutput.additionalContext | contains("there is no skip latch")) and
  ((.hookSpecificOutput.additionalContext | contains("skipped for this session")) | not)
' <<<"$OUT_SC" >/dev/null 2>&1; then
  ok "shellcheck-absent -> notice-only latch + PATH diagnostic (#2732)"
else
  fail "shellcheck-absent latch/PATH diagnostic wrong: $OUT_SC"
fi
OUT_SC2=$(run_no_tools "$REPO/clean.sh")
if [[ -z "$OUT_SC2" ]]; then
  ok "shellcheck-absent -> second run same session is silent (once-per-session)"
else
  fail "shellcheck-absent second run not silent: $OUT_SC2"
fi

# shfmt-absent WITH .editorconfig opt-in + shellcheck PRESENT with findings ->
# ONE JSON document: findings in additionalContext, shfmt notice on both
# channels (composition contract: a hook's stdout is a single JSON doc).
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v shellcheck)" >"$FAKEBIN/shellcheck"
chmod +x "$FAKEBIN/shellcheck"
REPO_MIX="$WORK/mixrepo"
new_repo "$REPO_MIX"
cat >"$REPO_MIX/.editorconfig" <<'EOF'
root = true

[*.sh]
indent_style = space
indent_size = 2
EOF
printf '#!/bin/bash\ncd /tmp\necho done\n' >"$REPO_MIX/finding.sh"
MIX_DATA="$(mktemp -d "$WORK/plugdata.XXXXXX")"
OUT_MIX=$(
  cd "$UNRELATED" || exit 1
  printf '{"session_id":"test-mix-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_MIX/finding.sh" |
    env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$MIX_DATA" \
      CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true bash "$HOOK"
)
RC_MIX=$?
if [[ $RC_MIX -eq 0 ]]; then ok "shfmt-absent+findings -> exit 0"; else fail "shfmt-absent+findings exit $RC_MIX"; fi
DOCS=$(jq -s 'length' <<<"$OUT_MIX" 2>/dev/null)
if [[ "$DOCS" == "1" ]]; then
  ok "shfmt-absent+findings -> single JSON document on stdout"
else
  fail "shfmt-absent+findings: stdout is not one JSON doc (docs=$DOCS): $OUT_MIX"
fi
if jq -e '(.hookSpecificOutput.additionalContext | contains("SC2164"))
  and (.hookSpecificOutput.additionalContext | contains("shfmt"))
  and (.systemMessage | contains("shfmt"))
  and (.systemMessage | contains("SC2164") | not)' <<<"$OUT_MIX" >/dev/null 2>&1; then
  ok "shfmt-absent+findings -> findings on agent channel, notice on both, findings not in systemMessage"
else
  fail "shfmt-absent+findings: composition wrong: $OUT_MIX"
fi

# jq-absent -> visible once-per-session notice (input parsing gate).
rm -f "$FAKEBIN/jq"
JQ_DATA="$(mktemp -d "$WORK/plugdata.XXXXXX")"
OUT_NOJQ=$(
  cd "$UNRELATED" || exit 1
  printf '{"session_id":"test-nojq-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/clean.sh" |
    env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$JQ_DATA" \
      CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true bash "$HOOK"
)
RC_NOJQ=$?
if [[ $RC_NOJQ -eq 0 && "$OUT_NOJQ" == *'"systemMessage"'* && "$OUT_NOJQ" == *jq* ]]; then
  ok "jq-absent -> exit 0 with visible notice"
else
  fail "jq-absent (rc=$RC_NOJQ out=$OUT_NOJQ)"
fi
# Out-of-scope edit (a .md file) with jq absent -> fully silent: the jq-free
# applicability pre-filter must run before the jq gate.
JQ_DATA2="$(mktemp -d "$WORK/plugdata.XXXXXX")"
OUT_OOS=$(
  cd "$UNRELATED" || exit 1
  printf '{"session_id":"test-oos-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/README.md" |
    env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$JQ_DATA2" \
      CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true bash "$HOOK"
)
RC_OOS=$?
if [[ $RC_OOS -eq 0 && -z "$OUT_OOS" ]]; then
  ok "jq-absent + out-of-scope edit -> fully silent (pre-filter before gate)"
else
  fail "jq-absent out-of-scope edit (rc=$RC_OOS out=$OUT_OOS)"
fi

# --- hooks.json: the if rows equal the script's own extension set (#3411) ----
# The if rows are what keep a Write or Edit of any other file from spawning
# this hook: Claude Code evaluates a handler's `if` at match time and drops the
# handler without a spawn (hooks reference, `if`, re-fetched 2026-09-07; the
# installed CLI logs "Skipping hook due to if condition ... not matching"), and
# an Edit(...) rule is the one consulted for Write and NotebookEdit as well.
# The script's own filter stays as defense in depth, so the two sets must be
# IDENTICAL: an if row the script does not handle spawns a process that exits
# at the filter, and an extension the script handles with no if row is a silent
# regression, since the hook then never runs for it.
#
# The script's set is the glob list it hands hook::begin, lifted from that call
# with continuation lines joined the way bash joins them. One declaration
# serves both of the script's gates — the jq-free pre-filter and the re-check
# on the parsed path — so the two cannot disagree with each other and this
# pairing with the manifest is the only one left to check. An extraction that
# finds no call fails loudly below rather than passing on no evidence.
#
# On the manifest side every handler under every event and matcher group is
# read. Two things are pinned separately, since they answer different
# questions. The `if` rows, which paths a handler applies to: the values
# across every handler must be exactly the derived set, one row each, so a
# handler with no if, an if outside the set, a `Write(...)` rule, a duplicate
# row or an unfiltered group under any event fails. The group, which tools
# invoke the handler at all: every group must be PostToolUse with a matcher
# whose alternation is exactly Write and Edit in either order, the two tools
# whose payload carries a file this script formats (the rule validator folds
# Write and NotebookEdit into an Edit(...) rule, but the matcher is the tool
# name regex the harness consults first, and a matcher narrowed to one tool
# is the hook silently never running for the other, which no if row can show).
# The command must be the plugin's own script by either quoting placement,
# with no prefix, suffix or argument. What this does not reach is a
# registration outside hooks/hooks.json.
HOOKS_JSON="$HOOK_DIR/hooks.json"
BEGIN_LINE="$(awk '
  /^hook::begin[[:space:]]/ {
    line = $0
    while (line ~ /\\$/) {
      sub(/[[:space:]]*\\$/, "", line)
      if ((getline nxt) <= 0) break
      sub(/^[[:space:]]+/, "", nxt)
      line = line " " nxt
    }
    print line
    exit
  }' "$HOOK")"
SCRIPT_EXTS="$(printf '%s\n' "$BEGIN_LINE" |
  sed -n 's/^.*[[:space:]]PostToolUse[[:space:]][[:space:]]*//p' |
  tr -d "'\"" | tr ' ' '\n' | grep . | LC_ALL=C sort -u)"
EXPECTED_IF="$(printf '%s\n' "$SCRIPT_EXTS" | sed 's/.*/Edit(&)/' | tr '\n' ' ')"
EXPECTED_IF="${EXPECTED_IF% }"
EXPECTED_COUNT="$(printf '%s\n' "$SCRIPT_EXTS" | grep -c .)"
if command -v jq >/dev/null 2>&1 && [[ -f "$HOOKS_JSON" && -n "$BEGIN_LINE" && "$EXPECTED_COUNT" -gt 0 ]]; then
  # The one row outside this gate is the SessionStart prerequisite probe, exec
  # form behind the bash_format_enabled launcher gate, which is asserted on its
  # own here.
  ALL_HANDLERS="$(jq -c '[.hooks | to_entries[] | .key as $ev | .value[]? | .matcher as $m | .hooks[]? | . + {event: $ev, matcher: ($m // "(none)")}]' "$HOOKS_JSON")"
  PROBE_COUNT="$(jq -c --arg launcher '${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs' --arg probe '${CLAUDE_PLUGIN_ROOT}/hooks/probe-prerequisite.sh' '[.[] | select(.event == "SessionStart" and .command == "node" and .args == [$launcher, "--run-if-unset-or-true", "BASH_FORMAT_ENABLED", $probe])] | length' <<<"$ALL_HANDLERS")"
  HANDLERS="$(jq -c --arg launcher '${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs' --arg probe '${CLAUDE_PLUGIN_ROOT}/hooks/probe-prerequisite.sh' '[.[] | select((.event == "SessionStart" and .command == "node" and .args == [$launcher, "--run-if-unset-or-true", "BASH_FORMAT_ENABLED", $probe]) | not)]' <<<"$ALL_HANDLERS")"
  if [[ "$PROBE_COUNT" == "1" ]]; then
    ok "hooks.json: one exec-form SessionStart row runs probe-prerequisite.sh behind --run-if-unset-or-true BASH_FORMAT_ENABLED"
  else
    fail "hooks.json: expected one exec-form SessionStart probe-prerequisite.sh row behind --run-if-unset-or-true BASH_FORMAT_ENABLED, found $PROBE_COUNT"
  fi
  HANDLER_COUNT="$(jq 'length' <<<"$HANDLERS")"
  HANDLER_GROUPS="$(jq -r '[.[] | "\(.event):\(.matcher)"] | unique | join(",")' <<<"$HANDLERS")"
  GROUPS_OFF="$(jq -r '[.[] | select(.event != "PostToolUse" or ((.matcher | split("|") | sort | unique) != ["Edit", "Write"])) | "\(.event):\(.matcher)"] | unique | join(",")' <<<"$HANDLERS")"
  IF_VALUES="$(jq -r '[.[] | (.if // "(none)")] | sort | join(" ")' <<<"$HANDLERS")"
  WRITE_IF="$(jq '[.[] | select(has("if") and (.if | startswith("Write(")))] | length' <<<"$HANDLERS")"
  CMD_OFF="$(jq -r --arg script '${CLAUDE_PLUGIN_ROOT}/hooks/bash-format.sh' '
    [.[] | select(
      ((.command == "node") and ((.args // []) | index($script)))
      | not) | (.command // "(none)")] | unique | join(",")' <<<"$HANDLERS")"
  if [[ "$HANDLER_COUNT" == "$EXPECTED_COUNT" && "$IF_VALUES" == "$EXPECTED_IF" && "$WRITE_IF" == "0" && -z "$GROUPS_OFF" && -z "$CMD_OFF" ]]; then
    ok "hooks.json: every handler ($HANDLER_GROUPS) is a PostToolUse Write and Edit group running the plugin's script, and the if rows are exactly $EXPECTED_IF, the script's own hook::begin glob list"
  else
    fail "hooks.json launch gate: handlers=$HANDLER_COUNT/$EXPECTED_COUNT groups=$HANDLER_GROUPS groups_off='$GROUPS_OFF' if='$IF_VALUES' expected='$EXPECTED_IF' write_if=$WRITE_IF cmd_off='$CMD_OFF'"
  fi
else
  fail "hooks.json launch-gate assertions need jq, $HOOKS_JSON and a hook::begin glob list in the script (begin='$BEGIN_LINE' globs=(${SCRIPT_EXTS//$'\n'/ }))"
fi

# --- Gitignored path (#4671): neither rewritten nor reported by default ------
# The fixture would be reformatted (unindented if-block) AND reported
# (SC2154), so an empty stdout and unchanged bytes prove the skip. The opt-in
# run is the non-vacuity half: the same file IS rewritten once the gate opens.
REPO_IGN="$WORK/gitignored"
new_repo "$REPO_IGN"
git -C "$REPO_IGN" config core.excludesFile /dev/null
printf '.work/\n' >"$REPO_IGN/.gitignore"
printf 'root = true\n[*.sh]\nindent_style = space\nindent_size = 2\n' >"$REPO_IGN/.editorconfig"
mkdir -p "$REPO_IGN/.work"
# shellcheck disable=SC2016  # $undefined_variable must stay literal in the emitted fixture
IGN_BODY='#!/usr/bin/env bash\nif true; then\necho "$undefined_variable"\nfi\n'
# shellcheck disable=SC2059  # the body is the format string on purpose: it carries the \n escapes
printf "$IGN_BODY" >"$REPO_IGN/.work/scratch.sh"
IGN_BEFORE="$(cat "$REPO_IGN/.work/scratch.sh")"
OUT=$(run_hook "$REPO_IGN/.work/scratch.sh")
if [[ -z "$OUT" ]]; then ok "gitignored: no findings reported"; else fail "gitignored: reported: $OUT"; fi
if [[ "$(cat "$REPO_IGN/.work/scratch.sh")" == "$IGN_BEFORE" ]]; then
  ok "gitignored: file not rewritten"
else
  fail "gitignored: file was rewritten: $(cat "$REPO_IGN/.work/scratch.sh")"
fi
if [[ $HAVE_SHFMT -eq 1 ]]; then
  OUT=$(run_hook_env "$REPO_IGN/.work/scratch.sh" CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true \
    CLAUDE_PLUGIN_OPTION_BASH_FORMAT_LINT_GITIGNORED=true)
  if grep -q '^  echo' "$REPO_IGN/.work/scratch.sh"; then
    ok "gitignored + bash_format_lint_gitignored=true: file formatted"
  else
    fail "gitignored + opt-in: not formatted: $(cat "$REPO_IGN/.work/scratch.sh")"
  fi
fi

# --- Notice text is bound to prerequisites.json --------------------------------
# The hook does not read the manifest at run time (parse cost on the per-edit hot
# path), so this case is the binding: the manifest declares shfmt and shellcheck,
# and each tool's missing-binary notice call states that tool's name, check and
# install, verbatim.
PLUGIN_ROOT="${HOOK_DIR%/*}"
MANIFEST="$PLUGIN_ROOT/prerequisites.json"
HOOKS_JSON="$HOOK_DIR/hooks.json"
if command -v jq >/dev/null 2>&1 && [[ -f "$MANIFEST" ]]; then
  if jq -e '(.tools | map(.name) | sort) == ["jq", "node", "shellcheck", "shfmt"]' "$MANIFEST" >/dev/null 2>&1; then
    ok "manifest: declares exactly shfmt, shellcheck jq and node"
  else
    fail "manifest: expected tools shfmt, shellcheck jq and node: $(cat "$MANIFEST")"
  fi
  # assert_hook_states <tool> <field> <needle> <haystack>
  assert_hook_states() {
    if [[ -n "$3" ]] && grep -qF -- "$3" <<<"$4"; then
      ok "manifest binding: $1 notice states the manifest's $2 ($3)"
    else
      fail "manifest binding: $1 notice does not state the manifest's $2 (needle='$3')"
    fi
  }
  for MF_TOOL in shfmt shellcheck; do
    case "$MF_TOOL" in
    shfmt) NOTICE_VAR=SHFMT_NOTICE ;;
    *) NOTICE_VAR=SC_NOTICE ;;
    esac
    IFS=$'\t' read -r MF_CHECK MF_INSTALL < <(jq -r --arg n "$MF_TOOL" '.tools[] | select(.name == $n) | [.check, .install] | @tsv' "$MANIFEST")
    NOTICE_CALL="$(sed -n "/hook::tool_missing_notice_to $NOTICE_VAR/,/[^\\\\]\$/p" "$HOOK")"
    assert_hook_states "$MF_TOOL" name "'$MF_TOOL'" "$NOTICE_CALL"
    assert_hook_states "$MF_TOOL" check "$MF_CHECK" "$NOTICE_CALL"
    assert_hook_states "$MF_TOOL" install "$MF_INSTALL" "$NOTICE_CALL"
  done
else
  fail "manifest binding needs jq and $MANIFEST"
fi

# --- SessionStart probe honors bash_format_enabled ----------------------------
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
      ln -s "$exe" "$PG_WORK/sysbin/$base"
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
    done < <(jq -r '.tools[] | select(.name != "node") | [.name, .check, .install] | @tsv' "$MANIFEST")
    if [[ $RC_PG -eq 0 && $pg_ok -eq 1 ]]; then
      ok "probe-gate: $label -> notices name each tool, its check and the install line"
    else
      fail "probe-gate: $label should print a missing-tool notice per tool (rc=$RC_PG out=$OUT_PG)"
    fi
  done
  rm -rf "${PG_WORK:?}"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
