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
  s="$(mktemp -p "$WORK" sink.XXXXXX)"
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
  run_hook "$REPO_YES/src/fmt.sh" >/dev/null
  if grep -q '^  echo hi$' "$REPO_YES/src/fmt.sh"; then
    ok "shfmt gate ON (.editorconfig present) -> file formatted"
  else
    fail "shfmt gate ON -> not formatted: $(cat "$REPO_YES/src/fmt.sh")"
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
  # [*.md], no [*]) must NOT trigger formatting — otherwise shfmt would impose
  # its built-in defaults on shell files the repo never opted in for.
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

  # A [*] catch-all governs shell files, so formatting opts in.
  REPO_STAR="$WORK/star-config"
  new_repo "$REPO_STAR"
  printf 'root = true\n[*]\nindent_style = space\nindent_size = 2\n' >"$REPO_STAR/.editorconfig"
  printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_STAR/x.sh"
  run_hook "$REPO_STAR/x.sh" >/dev/null
  if grep -q '^  echo hi$' "$REPO_STAR/x.sh"; then
    ok "[*] catch-all .editorconfig -> shell file formatted"
  else
    fail "[*] catch-all -> shell file not formatted: $(cat "$REPO_STAR/x.sh")"
  fi

  # A brace-list section naming sh (`[*.{sh,bash}]`) governs shell files:
  # section_applies_to_shell matches the `{,sh,}` / `{sh,` / `,sh}` shapes, so
  # formatting opts in. Regression guard for the documented brace-list form,
  # previously exercised only via section_applies_to_shell's implementation.
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

# --- shfmt < 3.8 --apply-ignore fallback (`|| shfmt -w`) --------------------
# The format pass calls `shfmt --apply-ignore -w FILE || shfmt -w FILE`: shfmt
# 3.8+ honors --apply-ignore, older shfmt does not know the flag and fails, so
# the plain-`-w` fallback must still format. A stub shfmt that REJECTS
# --apply-ignore (simulating < 3.8) but formats on plain -w proves the fallback
# runs. Independent of the host's real shfmt: the stub is prepended to PATH.
STUBDIR="$(mktemp -d -p "$WORK" shfmtstub.XXXXXX)"
cat >"$STUBDIR/shfmt" <<'STUB'
#!/usr/bin/env bash
# Simulate shfmt < 3.8: --apply-ignore is an unknown flag -> fail, no format.
for a in "$@"; do
  [[ "$a" == "--apply-ignore" ]] && exit 2
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
FAKEBIN="$(mktemp -d -p "$WORK" fakebin.XXXXXX)"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink shellcheck shfmt; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done

# ShellCheck absent -> visible once-per-session notice on both channels.
rm -f "$FAKEBIN/shellcheck" "$FAKEBIN/shfmt"
SC_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
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
MIX_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
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
JQ_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
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
JQ_DATA2="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
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
