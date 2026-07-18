#!/usr/bin/env bash
# Black-box contract test for eol-normalizer.sh (the eol-normalizer plugin hook).
#
# Proves BEHAVIOR + WIRING: the hook fires on Write|Edit, resolves each file's
# eol from the consuming repo's own .gitattributes via git check-attr, normalizes
# CRLF->LF and LF->CRLF (both on every OS), no-ops on unspecified paths, skips
# binary content under text=auto, honors the kill switch, keeps stdout empty
# (advisory, exit 0), and emits a schema-valid telemetry envelope. No policy of its own — the fixture repo's
# .gitattributes is the sole authority.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures and
# .gitattributes. The hook is invoked as a subprocess from an UNRELATED cwd so
# any reliance on the caller's working directory would surface (the tools are
# file-anchored, so a correct hook needs no cd). git is required; without it the
# hook is a no-op and these assertions cannot fire, so the suite skips.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/eol-normalizer.sh"

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

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not on PATH -- eol-normalizer hook tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

cr_count() { tr -cd '\r' <"$1" | wc -c | tr -d ' '; }

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
    [[ -s "$f" ]] && return 0
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
# this isolates normalization behavior from path-form mismatch in the guard.
run_hook() {
  local file_path="$1"
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" \
      | env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED=true bash "$HOOK"
  )
}

# Same as run_hook but with caller-supplied extra env (NAME=VALUE / -u NAME ...).
run_hook_env() {
  local file_path="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" \
      | env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOK"
  )
}

REPO="$WORK/consumer"
new_repo "$REPO"
# The consuming repo's authority: .sh -> LF, .txt -> CRLF, .png unspecified.
printf '*.sh eol=lf\n*.txt eol=crlf\n' >"$REPO/.gitattributes"

# --- Case 1: LF arm (every OS) — CRLF .sh -> LF, exit 0, empty stdout --------
printf 'echo a\r\necho b\r\n' >"$REPO/seed.sh"
if [[ "$(cr_count "$REPO/seed.sh")" == "2" ]]; then ok "pre: seed.sh seeded with 2 CR"; else fail "pre: seed.sh CR=$(cr_count "$REPO/seed.sh")"; fi
OUT=$(run_hook "$REPO/seed.sh")
RC=$?
if [[ $RC -eq 0 ]]; then ok "LF arm .sh -> exit 0"; else fail "LF arm .sh exit $RC"; fi
if [[ -z "$OUT" ]]; then ok "LF arm .sh -> empty stdout (advisory)"; else fail "LF arm stdout not empty: $OUT"; fi
if [[ "$(cr_count "$REPO/seed.sh")" == "0" ]]; then ok "LF arm CRLF .sh -> 0 CR (every OS)"; else fail "LF arm .sh CR=$(cr_count "$REPO/seed.sh")"; fi

# --- Case 2: unspecified (.png) -> no-op, every OS ---------------------------
printf 'not really binary\r\n' >"$REPO/img.png"
OUT=$(run_hook "$REPO/img.png")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "unspecified .png -> exit 0 silent"; else fail "unspecified .png (rc=$RC out=$OUT)"; fi
if [[ "$(cr_count "$REPO/img.png")" == "1" ]]; then ok "unspecified .png -> CR preserved (no-op)"; else fail "unspecified .png normalized: CR=$(cr_count "$REPO/img.png")"; fi

# --- Case 3: kill switch bypasses -------------------------------------------
printf 'echo x\r\n' >"$REPO/off.sh"
OUT=$(run_hook_env "$REPO/off.sh" CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED=false)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch -> exit 0 silent"; else fail "kill switch (rc=$RC out=$OUT)"; fi
if [[ "$(cr_count "$REPO/off.sh")" == "1" ]]; then ok "kill switch -> CRLF preserved (not normalized)"; else fail "kill switch normalized despite off: CR=$(cr_count "$REPO/off.sh")"; fi

# --- Case 4: CRLF arm (every OS) — LF .txt -> CRLF ---------------------------
printf 'line one\nline two\n' >"$REPO/gap.txt"
OUT=$(run_hook "$REPO/gap.txt")
RC=$?
if [[ $RC -eq 0 ]]; then ok "CRLF arm .txt -> exit 0"; else fail "CRLF arm .txt exit $RC"; fi
if [[ "$(cr_count "$REPO/gap.txt")" == "2" ]]; then ok "CRLF arm LF .txt -> 2 CR (every OS)"; else fail "CRLF arm .txt CR=$(cr_count "$REPO/gap.txt") (expected 2)"; fi

# --- Case 5: text=auto binary guard — NUL content never rewritten ------------
# Under a broad `* text=auto eol=lf` rule, check-attr resolves eol=lf for
# binaries too; the hook must content-sniff and skip instead of corrupting.
AUTOREPO="$WORK/autorepo"
new_repo "$AUTOREPO"
printf '* text=auto eol=lf\n' >"$AUTOREPO/.gitattributes"
printf 'BIN\r\n\x00\x01\x02\r\ndata' >"$AUTOREPO/blob.bin"
BIN_BYTES_BEFORE=$(wc -c <"$AUTOREPO/blob.bin" | tr -d ' ')
OUT=$(run_hook "$AUTOREPO/blob.bin")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "binary guard -> exit 0 silent"; else fail "binary guard (rc=$RC out=$OUT)"; fi
if [[ "$(wc -c <"$AUTOREPO/blob.bin" | tr -d ' ')" == "$BIN_BYTES_BEFORE" && "$(cr_count "$AUTOREPO/blob.bin")" == "2" ]]; then
  ok "binary guard: NUL file under text=auto eol=lf left byte-identical"
else
  fail "binary guard: binary file was rewritten (bytes $(wc -c <"$AUTOREPO/blob.bin" | tr -d ' ')/$BIN_BYTES_BEFORE CR=$(cr_count "$AUTOREPO/blob.bin"))"
fi
# Text sibling in the same repo still normalizes (the sniff passes text through).
printf 'echo t\r\n' >"$AUTOREPO/auto.sh"
run_hook "$AUTOREPO/auto.sh" >/dev/null
if [[ "$(cr_count "$AUTOREPO/auto.sh")" == "0" ]]; then ok "binary guard: text file under text=auto still normalized"; else fail "binary guard: text file not normalized CR=$(cr_count "$AUTOREPO/auto.sh")"; fi

# --- Case 6: -text is never rewritten even with eol set ----------------------
printf '*.dat -text eol=lf\n' >>"$AUTOREPO/.gitattributes"
printf 'a\r\nb\r\n' >"$AUTOREPO/keep.dat"
run_hook "$AUTOREPO/keep.dat" >/dev/null
if [[ "$(cr_count "$AUTOREPO/keep.dat")" == "2" ]]; then ok "-text guard: CR preserved despite eol=lf"; else fail "-text guard: rewritten CR=$(cr_count "$AUTOREPO/keep.dat")"; fi

# --- Case 7: no-perl fallback preserves file mode (white-box) -----------------
# The mktemp fallback stages into a fresh temp file; without mode preservation
# a 755 script would come back non-executable. Shadow `command` so the lib's
# perl probe fails, forcing the fallback arm.
printf '#!/bin/sh\r\necho hi\r\n' >"$REPO/exec.sh"
chmod 755 "$REPO/exec.sh"
(
  # shellcheck disable=SC2329  # invoked indirectly: the sourced lib's `command -v perl` probe hits this shadow
  command() { if [[ "${1:-}" == "-v" && "${2:-}" == "perl" ]]; then return 1; fi; builtin command "$@"; }
  # Prove the shim actually hides perl before relying on it.
  if command -v perl >/dev/null 2>&1; then
    echo "FAIL: test shim: perl shadow ineffective" >&2
    exit 1
  fi
  # shellcheck source=normalize-eol.sh
  source "$HOOK_DIR/normalize-eol.sh"
  normalize_eol_to_lf "$REPO/exec.sh"
) || fail "fallback: subshell failed"
if [[ "$(cr_count "$REPO/exec.sh")" == "0" ]]; then ok "fallback: CRLF stripped without perl"; else fail "fallback: CR=$(cr_count "$REPO/exec.sh")"; fi
if [[ -x "$REPO/exec.sh" ]]; then ok "fallback: executable mode preserved"; else fail "fallback: exec bit lost"; fi

# ============================================================================
# Telemetry
# ============================================================================

# --- Sink unset -> empty stdout, exit 0 (parity) ----------------------------
printf 'echo p\r\n' >"$REPO/tel1.sh"
OUT_NS=$(run_hook_env "$REPO/tel1.sh" -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED=true)
RC_NS=$?
if [[ $RC_NS -eq 0 && -z "$OUT_NS" ]]; then
  ok "telemetry/sink-unset: exit 0, empty stdout (parity)"
else
  fail "telemetry/sink-unset: rc=$RC_NS out=$OUT_NS"
fi

# --- Stub sink + normalized .sh -> envelope status ok, action lf ------------
printf 'echo q\r\n' >"$REPO/tel2.sh"
TEL="$(mktemp)"
SINK="$(make_sink "cat >\"$TEL\"")"
run_hook_env "$REPO/tel2.sh" CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED=true HOOK_TELEMETRY_SINK="$SINK" >/dev/null
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
  if [[ "$(jq -r '.hook' "$TEL")" == "eol-normalizer" ]]; then ok "envelope: hook is eol-normalizer"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "envelope: status ok"; else fail "envelope: status=$(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.0" ]]; then ok "envelope: schema_version 1.0"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq -r '.data.action' "$TEL")" == "lf" ]]; then ok "envelope: data.action lf"; else fail "envelope: data.action=$(jq -r '.data.action' "$TEL")"; fi
  FREL=$(jq -r '.data.file' "$TEL")
  if [[ -n "$FREL" && "$FREL" != /* && "$FREL" != ?:* ]]; then ok "envelope: data.file repo-relative ($FREL)"; else fail "envelope: data.file not repo-relative: $FREL"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "envelope: duration_ms non-negative int"; else fail "envelope: duration_ms invalid ($(jq .duration_ms "$TEL"))"; fi
else
  fail "telemetry/stub-sink: no envelope written"
fi
rm -f "$TEL"

# --- Stub sink + unspecified .png -> status skipped, action skip ------------
printf 'x\r\n' >"$REPO/tel3.png"
TELS="$(mktemp)"
SINKS="$(make_sink "cat >\"$TELS\"")"
run_hook_env "$REPO/tel3.png" CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED=true HOOK_TELEMETRY_SINK="$SINKS" >/dev/null
wait_for_sink "$TELS"
if [[ -s "$TELS" ]]; then
  if [[ "$(jq -r '.status' "$TELS")" == "skipped" ]]; then ok "telemetry/unspecified: status skipped"; else fail "telemetry/unspecified: status=$(jq -r '.status' "$TELS")"; fi
  if [[ "$(jq -r '.data.action' "$TELS")" == "skip" ]]; then ok "telemetry/unspecified: action skip"; else fail "telemetry/unspecified: action=$(jq -r '.data.action' "$TELS")"; fi
else
  fail "telemetry/unspecified: no envelope written"
fi
rm -f "$TELS"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
