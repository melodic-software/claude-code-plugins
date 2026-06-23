#!/usr/bin/env bash
# Black-box contract test for markdown-format.sh (the markdown-formatter plugin hook).
#
# Proves WIRING, not baseline parity: that the hook fires on *.md/*.mdc, skips
# otherwise, runs markdownlint-cli2 --fix from the linted file's repo root
# (config discovery is CWD-anchored), preserves --fix bytes, and surfaces
# residual findings via additionalContext with no medley-policy prose.
#
# Self-contained: builds a throwaway git repo with its own markdownlint config
# and runtime-generated fixtures (CRLF preserved via printf, never committed —
# a committed CRLF fixture would be LF-normalized by .gitattributes). The hook
# is invoked as a subprocess from an UNRELATED cwd so the `cd repo-root` config
# discovery is genuinely exercised (running from the repo root would false-pass
# a hook that skips the cd).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/markdown-format.sh"

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

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

# --- Build the throwaway consumer repo --------------------------------------
REPO="$WORK/consumer"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name t

# Consumer's own markdownlint config — the cascade the hook must discover by
# cd-ing to the repo root. MD004 dash makes `*` markers a fixable violation;
# MD024 siblings_only makes a duplicate sibling heading an unfixable residual.
cat >"$REPO/.markdownlint-cli2.jsonc" <<'JSONC'
{
  "config": {
    "MD004": { "style": "dash" },
    "MD024": { "siblings_only": true },
    "MD013": false
  }
}
JSONC

# Invoke the hook as a subprocess from an unrelated cwd. CLAUDE_PROJECT_DIR is
# left UNSET so read_file_path's project-membership guard is disabled (it is not
# part of the fire-gate contract); this isolates formatting behavior from any
# POSIX-vs-Windows path-form mismatch in the guard.
run_hook() {
  local file_path="$1"
  (cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$file_path" \
    | env -u CLAUDE_PROJECT_DIR HOOK_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")
}

# --- Fixture A: fixable only (Path A) — clean after fix, no additionalContext -
# CRLF, no final newline. Only issue is the missing final newline (MD047);
# after --fix the file is clean → empty stdout.
FA="$REPO/fixtureA.md"
printf '# Title A\r\n\r\nSome text\r\n\r\n- item one\r\n- item two' >"$FA"

OUT_A="$(run_hook "$FA")"
RC_A=$?

if [[ $RC_A -eq 0 ]]; then ok "fixtureA exit 0"; else fail "fixtureA exit $RC_A"; fi
if [[ -z "$OUT_A" ]]; then ok "fixtureA empty stdout (clean after fix)"; else fail "fixtureA stdout not empty: $OUT_A"; fi
# --fix added a final newline; CRLF preserved.
EXPECT_A="$(printf '# Title A\r\n\r\nSome text\r\n\r\n- item one\r\n- item two\r\n')"
TAIL_A="$(tail -c 2 "$FA" | od -An -tx1 | tr -d ' \n')"
if [[ "$(cat "$FA")" == "$EXPECT_A" && "$TAIL_A" == "0d0a" ]]; then
  ok "fixtureA --fix added final newline, CRLF preserved"
else
  fail "fixtureA bytes wrong: $(od -c "$FA" | tail -3)"
fi

# --- Fixture B: fixable + unfixable (Path B) — fix applied + residual finding -
# `* star item` (MD004 dash, fixable) + duplicate sibling `## Section` (MD024,
# unfixable). --fix converts `*`→`-`; MD024 residual surfaces via context.
FB="$REPO/fixtureB.md"
printf '# Doc B\n\n## Section\n\ntext\n\n## Section\n\n* star item\n' >"$FB"

OUT_B="$(run_hook "$FB")"
RC_B=$?

if [[ $RC_B -eq 0 ]]; then ok "fixtureB exit 0"; else fail "fixtureB exit $RC_B"; fi
# Fixable MD004 applied: marker is now a dash.
if grep -q '^- star item$' "$FB" && ! grep -q '^\* star item$' "$FB"; then
  ok "fixtureB --fix applied MD004 dash"
else
  fail "fixtureB MD004 not fixed: $(cat "$FB")"
fi
# additionalContext carries the MD024 finding line (substring identity).
CTX_B=""
if [[ -n "$OUT_B" ]] && printf '%s' "$OUT_B" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX_B="$(printf '%s' "$OUT_B" | jq -r '.hookSpecificOutput.additionalContext')"
  ok "fixtureB emitted hookSpecificOutput.additionalContext"
else
  fail "fixtureB no additionalContext JSON: $OUT_B"
fi
if printf '%s' "$CTX_B" | grep -q 'fixtureB.md:7'; then
  ok "fixtureB ctx has finding line :7"
else
  fail "fixtureB ctx missing :7: $CTX_B"
fi
if printf '%s' "$CTX_B" | grep -q 'MD024'; then
  ok "fixtureB ctx names MD024"
else
  fail "fixtureB ctx missing MD024: $CTX_B"
fi
# Genericized wrapper: medley-policy tail must be gone.
if printf '%s' "$CTX_B" | grep -qi 'commit/CI will block'; then
  fail "fixtureB ctx still has medley policy tail"
else
  ok "fixtureB ctx dropped medley policy tail"
fi

# --- Fire gate: non-.md extension skips -------------------------------------
SKIP="$REPO/skip.other"
printf 'whatever\n' >"$SKIP"
OUT_S="$(run_hook "$SKIP")"
RC_S=$?
if [[ $RC_S -eq 0 && -z "$OUT_S" ]]; then
  ok "non-md extension skipped"
else
  fail "non-md not skipped (rc=$RC_S out=$OUT_S)"
fi

# --- Fire gate: non-existent .md skips --------------------------------------
OUT_M="$(run_hook "$REPO/does-not-exist.md")"
RC_M=$?
if [[ $RC_M -eq 0 && -z "$OUT_M" ]]; then
  ok "missing .md skipped"
else
  fail "missing .md not skipped (rc=$RC_M out=$OUT_M)"
fi

# --- Kill switch: disabled hook is a no-op ----------------------------------
OUT_K="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$FB" \
  | env -u CLAUDE_PROJECT_DIR HOOK_MARKDOWN_FORMAT_ENABLED=false bash "$HOOK")"
RC_K=$?
if [[ $RC_K -eq 0 && -z "$OUT_K" ]]; then
  ok "kill switch disables hook"
else
  fail "kill switch failed (rc=$RC_K out=$OUT_K)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
