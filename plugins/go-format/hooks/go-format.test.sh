#!/usr/bin/env bash
# Black-box contract test for go-format.sh (the go-format plugin hook).
#
# Proves WIRING: the hook fires only on *.go files (extension pre-filter),
# runs goimports UNCONDITIONALLY (no consumer-config opt-in gate — the one
# deliberate shape difference from ruff-format/typos-format; see
# docs/topics/832-go-ecosystem/PLAN.md Open Decision 1), skips files carrying
# Go's generated-code marker, autofixes imports/formatting in place, surfaces
# a syntax error as an advisory finding (not a tool break), honors the kill
# switch, and emits a schema-valid telemetry envelope.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# The hook is invoked from an UNRELATED cwd so any reliance on the caller's
# own working directory would surface.
#
# Requires a real goimports binary: $GOIMPORTS_TEST_BIN if set, else
# `goimports` on PATH. Without one the behavioral assertions cannot run, so
# the suite skips.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/go-format.sh"

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

# Resolve a real goimports binary. Skip the suite when none is available.
if [[ -n "${GOIMPORTS_TEST_BIN:-}" && -x "${GOIMPORTS_TEST_BIN}" ]]; then
  REAL_GOIMPORTS="${GOIMPORTS_TEST_BIN}"
elif command -v goimports >/dev/null 2>&1; then
  REAL_GOIMPORTS="$(command -v goimports)"
else
  echo "SKIP: no goimports binary (set GOIMPORTS_TEST_BIN or put goimports on PATH) -- go-format hook tests skipped"
  exit 0
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

new_go_repo() {
  local r="$1"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
}

# Invoke the hook from an unrelated cwd. CLAUDE_PROJECT_DIR is left UNSET so
# read_file_path's membership guard is disabled (not part of the fire gate).
run_hook() {
  local file_path="$1"
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true PATH="$(dirname "$REAL_GOIMPORTS"):$PATH" bash "$HOOK"
  )
}

# Same as run_hook but with caller-supplied extra env (NAME=VALUE ...).
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
new_go_repo "$REPO"

# --- Case 1: unconditional (no config anywhere) -> still runs ---------------
# Unlike ruff-format/typos-format, go-format has NO consumer-config opt-in
# gate — it must autofix even with zero Go-specific config present.
printf 'package main\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/needs_import.go"
OUT=$(run_hook "$REPO/needs_import.go")
RC=$?
if [[ $RC -eq 0 ]]; then ok "no config anywhere -> exit 0 (unconditional)"; else fail "no-config exit $RC"; fi
if grep -q 'import "fmt"' "$REPO/needs_import.go"; then
  ok "no config anywhere -> import still added (unconditional, no opt-in gate)"
else
  fail "no-config -> import not added: $(cat "$REPO/needs_import.go")"
fi

# --- Case 2: clean file -> exit 0, empty stdout ------------------------------
printf 'package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/clean.go"
OUT=$(run_hook "$REPO/clean.go")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean file -> exit 0"; else fail "clean file exit $RC"; fi
if [[ -z "$OUT" ]]; then ok "clean file -> empty stdout"; else fail "clean file stdout not empty: $OUT"; fi

# --- Case 3: import needed by edit -> auto-added in a subdir -----------------
mkdir -p "$REPO/src"
printf 'package main\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/src/fix.go"
OUT=$(run_hook "$REPO/src/fix.go")
RC=$?
if [[ $RC -eq 0 ]]; then ok "missing import (subdir) -> exit 0 (advisory)"; else fail "missing import exit $RC"; fi
if grep -q 'import "fmt"' "$REPO/src/fix.go"; then
  ok "missing import (subdir) -> auto-added"
else
  fail "missing import -> not added: $(cat "$REPO/src/fix.go")"
fi

# --- Case 4: unused import -> auto-removed -----------------------------------
printf 'package main\n\nimport (\n\t"fmt"\n\t"os"\n)\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/unused.go"
run_hook "$REPO/unused.go" >/dev/null
if ! grep -q '"os"' "$REPO/unused.go"; then
  ok "unused import -> auto-removed"
else
  fail "unused import -> still present: $(cat "$REPO/unused.go")"
fi

# --- Case 5: generated-file marker -> skipped, left untouched ---------------
printf '// Code generated by protoc-gen-go. DO NOT EDIT.\npackage main\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/generated.go"
BEFORE_GEN="$(cat "$REPO/generated.go")"
OUT=$(run_hook "$REPO/generated.go")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "generated-marker file -> exit 0, silent"; else fail "generated-marker not silent (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO/generated.go")" == "$BEFORE_GEN" ]]; then
  ok "generated-marker file -> left untouched (import NOT added despite being missing)"
else
  fail "generated-marker file -> was rewritten: $(cat "$REPO/generated.go")"
fi

# --- Case 5b: marker preceded by a license-header comment block -------------
# Common real-world shape (addlicense/goheader-style tooling prepends a
# copyright header before the generated-code marker) — the marker is NOT on
# the file's first non-blank line. The guard must still catch it.
printf '// Copyright 2026 Example Corp. All rights reserved.\n// Use of this source code is governed by a BSD-style\n// license that can be found in the LICENSE file.\n\n// Code generated by "stringer -type Op"; DO NOT EDIT.\npackage main\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/generated-header.go"
BEFORE_GH="$(cat "$REPO/generated-header.go")"
run_hook "$REPO/generated-header.go" >/dev/null
if [[ "$(cat "$REPO/generated-header.go")" == "$BEFORE_GH" ]]; then
  ok "generated-marker behind a license-header block -> still caught, left untouched"
else
  fail "generated-marker behind a license-header block -> was rewritten: $(cat "$REPO/generated-header.go")"
fi

# --- Case 5c: marker line has a trailing CRLF \r -----------------------------
printf '// Code generated by protoc-gen-go. DO NOT EDIT.\r\npackage main\r\n\r\nfunc main() {\r\n\tfmt.Println("hi")\r\n}\r\n' >"$REPO/generated-crlf.go"
BEFORE_CRLF="$(cat "$REPO/generated-crlf.go")"
run_hook "$REPO/generated-crlf.go" >/dev/null
if [[ "$(cat "$REPO/generated-crlf.go")" == "$BEFORE_CRLF" ]]; then
  ok "generated-marker with CRLF line endings -> still caught, left untouched"
else
  fail "generated-marker with CRLF line endings -> was rewritten"
fi

# --- Case 5d: UTF-8 BOM before the marker on the first line -----------------
printf '\xEF\xBB\xBF// Code generated by protoc-gen-go. DO NOT EDIT.\npackage main\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/generated-bom.go"
BEFORE_BOM="$(cat "$REPO/generated-bom.go")"
run_hook "$REPO/generated-bom.go" >/dev/null
if [[ "$(cat "$REPO/generated-bom.go")" == "$BEFORE_BOM" ]]; then
  ok "generated-marker with a leading UTF-8 BOM -> still caught, left untouched"
else
  fail "generated-marker with a leading UTF-8 BOM -> was rewritten"
fi

# --- Case 5e: marker AFTER the leading comment/blank block -> NOT generated -
# The marker must appear before the first non-comment, non-blank line to
# count — a file that merely mentions the marker text after `package main`
# has already started is real (or at least not-provably-generated) code and
# must still be formatted normally.
printf 'package main\n\n// Code generated by protoc-gen-go. DO NOT EDIT.\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/not-generated.go"
run_hook "$REPO/not-generated.go" >/dev/null
if grep -q 'import "fmt"' "$REPO/not-generated.go"; then
  ok "marker after leading block -> not treated as generated, import still added"
else
  fail "marker after leading block -> wrongly treated as generated: $(cat "$REPO/not-generated.go")"
fi

# --- Case 6: non-.go extension -> hook does not fire -------------------------
printf 'this is not go' >"$REPO/notes.txt"
BEFORE_TXT="$(cat "$REPO/notes.txt")"
OUT=$(run_hook "$REPO/notes.txt")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "non-.go file -> exit 0, silent"; else fail "non-.go file not silent (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO/notes.txt")" == "$BEFORE_TXT" ]]; then ok "non-.go file -> untouched"; else fail "non-.go file -> was modified"; fi

# --- Case 7: syntax error -> surfaced as advisory finding, not a tool break --
printf 'package main\n\nfunc main() {\n\tfmt.Println("hi"\n}\n' >"$REPO/syntax.go"
OUT=$(run_hook "$REPO/syntax.go")
RC=$?
if [[ $RC -eq 0 ]]; then ok "syntax error -> exit 0 (advisory)"; else fail "syntax error exit $RC (must be advisory)"; fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -qi 'syntax error'; then
    ok "syntax error -> surfaced in additionalContext as a finding"
  else
    fail "syntax error ctx wrong shape: $CTX"
  fi
else
  fail "syntax error -> no additionalContext JSON: $OUT"
fi

# --- Case 8: kill switch bypasses hook ---------------------------------------
printf 'package main\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/kill.go"
BEFORE_K="$(cat "$REPO/kill.go")"
OUT=$(run_hook_env "$REPO/kill.go" PATH="$(dirname "$REAL_GOIMPORTS"):$PATH" CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=false)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch off -> exit 0 silent"; else fail "kill switch failed (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO/kill.go")" == "$BEFORE_K" ]]; then ok "kill switch -> file untouched"; else fail "kill switch -> file was modified"; fi

# ============================================================================
# Telemetry
# ============================================================================

# --- Sink unset -> empty stdout, exit 0 (parity) ------------------------------
printf 'package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/tel-clean.go"
OUT_NS=$(run_hook_env "$REPO/tel-clean.go" -u HOOK_TELEMETRY_SINK PATH="$(dirname "$REAL_GOIMPORTS"):$PATH" CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true)
RC_NS=$?
if [[ $RC_NS -eq 0 && -z "$OUT_NS" ]]; then
  ok "telemetry/sink-unset: exit 0, empty stdout (parity)"
else
  fail "telemetry/sink-unset: rc=$RC_NS out=$OUT_NS"
fi

# --- Stub sink + syntax-error finding -> envelope status ok with findings ---
printf 'package main\n\nfunc main() {\n\tfmt.Println("hi"\n}\n' >"$REPO/tel.go"
TEL="$(mktemp)"
SINK="$(make_sink "cat >\"$TEL\"")"
run_hook_env "$REPO/tel.go" PATH="$(dirname "$REAL_GOIMPORTS"):$PATH" CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINK" >/dev/null
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
  if [[ "$(jq -r '.hook' "$TEL")" == "go-format" ]]; then ok "envelope: hook is go-format"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "envelope: status ok"; else fail "envelope: status=$(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.0" ]]; then ok "envelope: schema_version 1.0"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq '.data.findings | length' "$TEL")" -ge 1 ]]; then ok "envelope: findings populated"; else fail "envelope: findings empty ($(jq '.data.findings' "$TEL"))"; fi
  if jq -e '.data.findings[0] | type == "string"' "$TEL" >/dev/null 2>&1; then ok "envelope: findings are flat strings"; else fail "envelope: findings[0] wrong type ($(jq '.data.findings[0]' "$TEL"))"; fi
  FREL=$(jq -r '.data.file' "$TEL")
  if [[ -n "$FREL" && "$FREL" != /* && "$FREL" != ?:* ]]; then ok "envelope: data.file repo-relative ($FREL)"; else fail "envelope: data.file not repo-relative: $FREL"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "envelope: duration_ms non-negative int"; else fail "envelope: duration_ms invalid ($(jq .duration_ms "$TEL"))"; fi
  if ! printf '%s' "$OUT" | grep -q schema_version 2>/dev/null; then ok "envelope: never leaked into hook's own stdout"; else fail "envelope leaked into stdout"; fi
else
  fail "telemetry/stub-sink: no envelope written"
fi
rm -f "$TEL"

# --- Stub sink + kill switch -> status skipped -------------------------------
printf 'package main\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/tel2.go"
TELS="$(mktemp)"
SINKS="$(make_sink "cat >\"$TELS\"")"
run_hook_env "$REPO/tel2.go" PATH="$(dirname "$REAL_GOIMPORTS"):$PATH" CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=false HOOK_TELEMETRY_SINK="$SINKS" >/dev/null
if [[ -s "$TELS" ]]; then
  fail "telemetry/kill-switch: envelope written despite kill switch (should exit before telemetry)"
else
  ok "telemetry/kill-switch: no envelope written (hook exits before telemetry setup)"
fi
rm -f "$TELS"

# --- Missing-tool visibility (dim-9 doctrine) --------------------------------
# Fake-bin dir of exec wrappers (no goimports): a *.go edit must produce a
# visible once-per-session skip notice on both channels, silent on the
# second run. jq removal then exercises the input-parsing gate.
FAKEBIN="$(mktemp -d -p "$WORK" fakebin.XXXXXX)"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink rm; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
REPO_NG="$WORK/no-goimports"
mkdir -p "$REPO_NG"
git -C "$REPO_NG" init -q
printf 'package main\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO_NG/app.go"
NG_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
run_ng() {
  (
    cd "$UNRELATED" || return 1
    printf '{"session_id":"test-nogoimports-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_NG/app.go" |
      env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$NG_DATA" \
        CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true bash "$HOOK"
  )
}
OUT_NG=$(run_ng)
RC_NG=$?
if [[ $RC_NG -eq 0 ]]; then ok "goimports-absent -> exit 0"; else fail "goimports-absent exit $RC_NG"; fi
if jq -e '(.systemMessage | contains("goimports")) and (.hookSpecificOutput.additionalContext | contains("goimports"))' <<<"$OUT_NG" >/dev/null 2>&1; then
  ok "goimports-absent -> visible notice on both channels"
else
  fail "goimports-absent: notice missing or malformed: $OUT_NG"
fi
OUT_NG2=$(run_ng)
if [[ -z "$OUT_NG2" ]]; then
  ok "goimports-absent -> second run same session is silent (once-per-session)"
else
  fail "goimports-absent second run not silent: $OUT_NG2"
fi

# jq-absent -> visible once-per-session notice (input parsing gate).
rm -f "$FAKEBIN/jq"
JQ_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
OUT_NOJQ=$(
  cd "$UNRELATED" || exit 1
  printf '{"session_id":"test-nojq-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_NG/app.go" |
    env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$JQ_DATA" \
      CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true bash "$HOOK"
)
RC_NOJQ=$?
if [[ $RC_NOJQ -eq 0 && "$OUT_NOJQ" == *'"systemMessage"'* && "$OUT_NOJQ" == *jq* ]]; then
  ok "jq-absent -> exit 0 with visible notice"
else
  fail "jq-absent (rc=$RC_NOJQ out=$OUT_NOJQ)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
