#!/usr/bin/env bash
# Black-box contract test for statusline-shim.sh (the version-independent
# locator the operator wires into their statusline).
#
# Proves: (a) RESOLUTION — the newest installed tee by mtime wins across
# version directories whose names do NOT sort lexically (0.10.0 vs 0.9.0),
# transient temp_* marketplace clones are skipped, the marketplace directory
# name is never assumed, and other plugins' trees are ignored; (b)
# TRANSPARENCY — the wrapped statusline command receives the stdin bytes and
# its stdout and exit code pass through, whether the tee was found or not;
# (c) the NO-TEE paths — a missing tee degrades to running the wrapped command
# alone, and with no wrapped command the shim prints one diagnostic line and
# exits 0 rather than exec'ing an empty argv; (d) CHAINING — two shims in
# series each locate their own tee and the innermost command still owns
# stdout, which is how rate-limit-guard and context-guard compose.
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM="$SCRIPT_DIR/statusline-shim.sh"

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
assert_eq() {
  local want="$1" got="$2" what="$3"
  if [[ "$want" == "$got" ]]; then
    ok "$what"
  else
    fail "$what — want [$want] got [$got]"
  fi
}
assert_contains() {
  local hay="$1" needle="$2" what="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    ok "$what"
  else
    fail "$what — [$hay] does not contain [$needle]"
  fi
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

INPUT='{"session_id":"sess-42","context_window":{"used_percentage":8}}'

# Plant a fake tee that identifies itself, then behaves like the real one:
# transparent passthrough of stdin, stdout, and exit code.
#   $1 = HOME root, $2 = marketplace dir, $3 = plugin name, $4 = version,
#   $5 = marker printed to stderr when this tee runs
plant_tee() {
  local home="$1" mkt="$2" plugin="$3" version="$4" marker="$5"
  local dir="$home/.claude/plugins/cache/$mkt/$plugin/$version/scripts"
  mkdir -p "$dir"
  cat >"$dir/statusline-tee.sh" <<EOF
#!/usr/bin/env bash
echo "TEE:$marker" >&2
if ((\$#)); then exec "\$@"; fi
echo "standalone:$marker"
EOF
  printf '%s' "$dir/statusline-tee.sh"
}

# Wrapped statusline stand-in: echoes the stdin it received, prints a fixed
# line, and exits with a chosen code.
make_wrapped() {
  local path="$1" rc="$2"
  cat >"$path" <<EOF
#!/usr/bin/env bash
echo "stdin:\$(cat)"
echo "RENDER"
exit $rc
EOF
  chmod +x "$path"
}

# Runner: HOME-scoped invocation; remaining args are the wrapped command.
# Captures stdout, stderr, and the exit code.
OUT=""
ERR=""
RC=0
run() {
  local home="$1"
  shift
  local errfile="$WORK/stderr.$$"
  OUT="$(printf '%s' "$INPUT" | HOME="$home" bash "$SHIM" "$@" 2>"$errfile")"
  RC=$?
  ERR="$(cat "$errfile")"
  rm -f "$errfile"
}

# --- 1. single installed tee: resolved, and the chain stays transparent -----
H1="$WORK/h1"
plant_tee "$H1" "some-marketplace" "rate-limit-guard" "0.1.0" "v1" >/dev/null
make_wrapped "$H1/render.sh" 0
run "$H1" bash "$H1/render.sh"
assert_contains "$ERR" "TEE:v1" "resolves the installed tee (marketplace name not assumed)"
assert_contains "$OUT" "stdin:$INPUT" "stdin bytes reach the wrapped command"
assert_contains "$OUT" "RENDER" "wrapped command owns stdout"
assert_eq "0" "$RC" "wrapped exit code passes through (0)"

# --- 2. exit code of the wrapped command is preserved, not swallowed --------
make_wrapped "$H1/render-fail.sh" 3
run "$H1" bash "$H1/render-fail.sh"
assert_eq "3" "$RC" "nonzero wrapped exit code passes through"

# --- 3. newest by MTIME wins, and lexical order would get it wrong ----------
# 0.9.0 is lexically LAST (a naive glob loop would pick it) but 0.10.0 is the
# newer install; the shim must pick 0.10.0.
H2="$WORK/h2"
OLD="$(plant_tee "$H2" "mkt" "rate-limit-guard" "0.9.0" "old")"
NEW="$(plant_tee "$H2" "mkt" "rate-limit-guard" "0.10.0" "new")"
touch -t 202001010000 "$OLD"
touch -t 203001010000 "$NEW"
make_wrapped "$H2/render.sh" 0
run "$H2" bash "$H2/render.sh"
assert_contains "$ERR" "TEE:new" "newest-by-mtime version wins over lexically-later name"

# --- 4. transient temp_* marketplace clones are skipped ---------------------
H3="$WORK/h3"
REAL="$(plant_tee "$H3" "melodic-software" "rate-limit-guard" "0.1.0" "real")"
TMP="$(plant_tee "$H3" "temp_git_1784663154120_oirbvy" "rate-limit-guard" "0.1.0" "tempclone")"
touch -t 202001010000 "$REAL"
touch -t 203001010000 "$TMP" # newer, and must STILL lose
make_wrapped "$H3/render.sh" 0
run "$H3" bash "$H3/render.sh"
assert_contains "$ERR" "TEE:real" "temp_* marketplace clone skipped even when newer"

# --- 5. other plugins' trees are ignored ------------------------------------
H4="$WORK/h4"
plant_tee "$H4" "mkt" "context-guard" "0.1.0" "sibling" >/dev/null
make_wrapped "$H4/render.sh" 0
run "$H4" bash "$H4/render.sh"
assert_eq "" "$ERR" "another plugin's tee is not resolved"
assert_contains "$OUT" "RENDER" "wrapped command still runs when no tee is found"
assert_eq "0" "$RC" "no-tee passthrough preserves exit code (0)"

# --- 6. no tee + failing wrapped command: still transparent -----------------
make_wrapped "$H4/render-fail.sh" 7
run "$H4" bash "$H4/render-fail.sh"
assert_eq "7" "$RC" "no-tee passthrough preserves a nonzero exit code"

# --- 7. no tee AND no wrapped command: one notice, exit 0, no empty exec ----
run "$H4"
assert_contains "$OUT" "rate-limit-guard" "standalone no-tee case names the plugin"
assert_contains "$OUT" "setup check" "standalone no-tee case points at the setup remediation"
assert_eq "0" "$RC" "standalone no-tee case exits 0"
# $() strips the trailing newline, so re-add one before counting.
assert_eq "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "standalone no-tee notice is one line"

# --- 8. tee found, no wrapped command: the tee's standalone mode runs -------
run "$H1"
assert_contains "$OUT" "standalone:v1" "no wrapped command hands standalone mode to the tee"

# --- 9. HOME unset: nothing to resolve, wrapped command unaffected ----------
make_wrapped "$WORK/render-nohome.sh" 0
OUT="$(printf '%s' "$INPUT" | env -u HOME bash "$SHIM" bash "$WORK/render-nohome.sh" 2>/dev/null)"
RC=$?
assert_contains "$OUT" "RENDER" "unset HOME degrades to the wrapped command"
assert_eq "0" "$RC" "unset HOME preserves the wrapped exit code"

# --- 10. chaining: two shims in series, each resolving its own tee ----------
# This is the two-plugin composition: rate-limit-guard shim wraps context-guard
# shim wraps the operator's statusline.
H5="$WORK/h5"
plant_tee "$H5" "melodic-software" "rate-limit-guard" "0.1.0" "rlg" >/dev/null
plant_tee "$H5" "melodic-software" "context-guard" "0.1.0" "cg" >/dev/null
# A sibling shim for the second link: same source, different plugin name.
SIB="$WORK/rlg-shim.sh"
sed 's/^PLUGIN_NAME="rate-limit-guard"$/PLUGIN_NAME="context-guard"/' "$SHIM" >"$SIB"
make_wrapped "$H5/render.sh" 0
run "$H5" bash "$SIB" bash "$H5/render.sh"
assert_contains "$ERR" "TEE:rlg" "chain: rate-limit-guard tee runs"
assert_contains "$ERR" "TEE:cg" "chain: context-guard tee runs"
assert_contains "$OUT" "stdin:$INPUT" "chain: stdin bytes survive both hops"
assert_contains "$OUT" "RENDER" "chain: innermost command owns stdout"
assert_eq "0" "$RC" "chain: exit code passes through both hops"

# --- 11. chain with a missing middle tee stays transparent ------------------
H6="$WORK/h6"
plant_tee "$H6" "melodic-software" "rate-limit-guard" "0.1.0" "rlg" >/dev/null
make_wrapped "$H6/render.sh" 0
run "$H6" bash "$SIB" bash "$H6/render.sh"
assert_contains "$ERR" "TEE:rlg" "chain: present tee still runs when the sibling tee is absent"
assert_contains "$OUT" "RENDER" "chain: absent sibling tee does not break the statusline"

echo
echo "passed: $PASS  failed: $FAIL"
((FAIL == 0))
