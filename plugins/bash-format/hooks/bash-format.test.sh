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

# make_sink <body> -> path to an executable single-command stub sink running
# <body> (which reads the envelope on stdin). HOOK_TELEMETRY_SINK must be a
# single executable path, not a command-with-args, so tests point it at a stub.
make_sink() {
  local s
  s="$(mktemp "$WORK/sink.XXXXXX")"
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$1"
  } >"$s"
  chmod +x "$s"
  printf '%s' "$s"
}

# wait_for_sink <file> [tries] -> block until <file> is non-empty (the
# fire-and-forget sink flushed) or the bound elapses, polling in 20ms steps.
wait_for_sink() {
  local f="$1" tries="${2:-150}"
  while ((tries-- > 0)); do
    if [[ -s "$f" ]]; then
      return 0
    fi
    sleep 0.02
  done
  return 1
}

new_repo() {
  local r="$1"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
}

# Invoke the hook from an unrelated cwd. CLAUDE_PROJECT_DIR is left UNSET so
# read_file_path's membership guard is disabled (not part of the fire gate);
# this isolates lint/format behavior from path-form mismatch in the guard.
run_hook() {
  local file_path="$1"
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true bash "$HOOK"
  )
}

# Same as run_hook but with caller-supplied extra env (NAME=VALUE ...) and an
# optional override of CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED, passed through env.
run_hook_env() {
  local file_path="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOK"
  )
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
REPO_IGN="$WORK/apply-ignore-transient"
new_repo "$REPO_IGN"
printf 'root = true\n[*.sh]\nignore = true\n' >"$REPO_IGN/.editorconfig"
printf '#!/usr/bin/env bash\nif true; then\n  echo hi\nfi\n' >"$REPO_IGN/x.sh"
# Byte-for-byte reference: `$(cat)` strips trailing newlines, so a string
# compare would report a difference the file does not have.
cp "$REPO_IGN/x.sh" "$WORK/apply-ignore-transient.expected"
(
  cd "$UNRELATED" || exit 1
  printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_IGN/x.sh" |
    env -u CLAUDE_PROJECT_DIR PATH="$STUBDIR2:$PATH" \
      CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=true bash "$HOOK" >/dev/null
)
if cmp -s "$REPO_IGN/x.sh" "$WORK/apply-ignore-transient.expected"; then
  ok "failed --apply-ignore run does not re-format without the flag"
else
  fail "opt-out discarded by fallback: $(cat "$REPO_IGN/x.sh")"
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
  for field in schema_version timestamp hook hook_event status duration_ms data; do
    if jq -e "has(\"$field\")" "$TEL" >/dev/null 2>&1; then
      ok "envelope: $field present"
    else
      fail "envelope: $field missing ($(cat "$TEL"))"
    fi
  done
  if [[ "$(jq -r '.hook' "$TEL")" == "bash-format" ]]; then ok "envelope: hook is bash-format"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "envelope: status ok"; else fail "envelope: status=$(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.0" ]]; then ok "envelope: schema_version 1.0"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq '.data.findings | length' "$TEL")" -ge 1 ]]; then ok "envelope: findings populated"; else fail "envelope: findings empty ($(jq '.data.findings' "$TEL"))"; fi
  if jq -e '.data.findings | any(test("SC2154"))' "$TEL" >/dev/null 2>&1; then ok "envelope: findings name SC2154"; else fail "envelope: findings missing SC2154 ($(jq '.data.findings' "$TEL"))"; fi
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

# --- Missing-tool visibility (dim-9 doctrine) --------------------------------
# Fake-bin dir of exec wrappers so individual tools can be removed from PATH
# without losing the coreutils the hook and the notice dedup need.
FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink shellcheck shfmt; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
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

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
