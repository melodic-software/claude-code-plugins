#!/usr/bin/env bash
# Tests for scripts/check-hooks-description.sh: a fixture tree per case so the
# verdict is on the shape under test and nothing else, then the live tree.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-hooks-description.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts" "$dir/plugins"
  cp "$SCRIPT" "$dir/scripts/check-hooks-description.sh"
  chmod +x "$dir/scripts/check-hooks-description.sh"
  printf '%s' "$dir"
}

hooks_file() { # <fixture> <plugin> <content>
  mkdir -p "$1/plugins/$2/hooks"
  printf '%s\n' "$3" >"$1/plugins/$2/hooks/hooks.json"
}

run_check() (
  cd "$1" && bash scripts/check-hooks-description.sh
)

LABELED='{"description":"Formats Go source and its imports after a write or edit.","hooks":{"PostToolUse":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":"x"}]}]}}'
UNLABELED='{"hooks":{"PostToolUse":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":"x"}]}]}}'

# --- the shape the gate exists to reject: no description at all --------------
f="$(new_fixture)"
hooks_file "$f" alpha "$UNLABELED"
if out="$(run_check "$f" 2>&1)"; then
  fail "a hooks.json without a description should fail, got success: $out"
else
  if echo "$out" | grep -q 'HOOKS DESCRIPTION: plugins/alpha/hooks/hooks.json: no top-level "description"'; then
    ok "missing description fails and names the file"
  else
    fail "expected the missing-description line naming plugins/alpha, got: $out"
  fi
fi
rm -rf "$f"

# --- a labeled file passes, and a plugin with no hooks dir is skipped --------
f="$(new_fixture)"
hooks_file "$f" alpha "$LABELED"
mkdir -p "$f/plugins/beta/skills/x"
if out="$(run_check "$f" 2>&1)"; then
  if echo "$out" | grep -q 'Every plugin hooks.json (1) carries'; then
    ok "a labeled file passes and a hook-less plugin is not counted"
  else
    fail "expected the clean statement counting 1 file, got: $out"
  fi
else
  fail "a labeled hooks.json should pass, got: $out"
fi
rm -rf "$f"

# --- the degenerate values a present key can still carry ---------------------
for case in \
  'blank|{"description":"","hooks":{}}|is blank' \
  'whitespace|{"description":"   ","hooks":{}}|is blank' \
  'number|{"description":7,"hooks":{}}|is not a string' \
  'null|{"description":null,"hooks":{}}|is not a string' \
  'multiline|{"description":"Formats Go.\nAnd more.","hooks":{}}|spans more than one line'; do
  IFS='|' read -r name content expect <<<"$case"
  f="$(new_fixture)"
  hooks_file "$f" alpha "$content"
  if out="$(run_check "$f" 2>&1)"; then
    fail "$name description should fail, got success: $out"
  else
    if echo "$out" | grep -q "HOOKS DESCRIPTION: plugins/alpha/hooks/hooks.json: .*$expect"; then
      ok "$name description fails with the right reason"
    else
      fail "$name description: expected '$expect' in the output, got: $out"
    fi
  fi
  rm -rf "$f"
done

# --- a CRLF checkout (Git Bash) does not read as multi-line -----------------
f="$(new_fixture)"
mkdir -p "$f/plugins/alpha/hooks"
printf '{\r\n  "description": "Formats Go source.",\r\n  "hooks": {}\r\n}\r\n' >"$f/plugins/alpha/hooks/hooks.json"
if run_check "$f" >/dev/null 2>&1; then
  ok "CRLF line endings between tokens are tolerated"
else
  fail "a CRLF-terminated hooks.json must pass; the line breaks sit outside the value"
fi
rm -rf "$f"

# --- every file is named, not only the first -------------------------------
f="$(new_fixture)"
hooks_file "$f" alpha "$UNLABELED"
hooks_file "$f" beta "$LABELED"
hooks_file "$f" gamma '{"description":"","hooks":{}}'
out="$(run_check "$f" 2>&1)"
if echo "$out" | grep -q 'plugins/alpha/hooks/hooks.json' && echo "$out" | grep -q 'plugins/gamma/hooks/hooks.json' && ! echo "$out" | grep -q 'plugins/beta/'; then
  ok "both failing files are named and the passing one is not"
else
  fail "expected alpha and gamma flagged, beta clean, got: $out"
fi
if echo "$out" | grep -q '2 problem(s) across 3 hooks.json file(s)'; then
  ok "the summary counts problems and files"
else
  fail "expected '2 problem(s) across 3 hooks.json file(s)', got: $out"
fi
rm -rf "$f"

# --- an unparsable file is a failure, never a silent clear -----------------
f="$(new_fixture)"
hooks_file "$f" alpha '{"description":"x", "hooks": '
if out="$(run_check "$f" 2>&1)"; then
  fail "unparsable hooks.json should fail, got success: $out"
else
  if echo "$out" | grep -q 'not parseable as JSON'; then
    ok "unparsable hooks.json fails closed"
  else
    fail "expected the parse-failure line, got: $out"
  fi
fi
rm -rf "$f"

# --- a well-formed document followed by trailing garbage is still a failure --
# jq prints a verdict for the first document and then exits non-zero on the
# garbage; the gate must read the status, not only the word (Codex, #3764).
f="$(new_fixture)"
hooks_file "$f" alpha '{"description":"Formats Go source.","hooks":{}} trailing'
if out="$(run_check "$f" 2>&1)"; then
  fail "trailing garbage after a labeled document should fail, got success: $out"
else
  if echo "$out" | grep -q 'not parseable as JSON'; then
    ok "trailing garbage after a labeled document fails closed"
  else
    fail "expected the parse-failure line for trailing garbage, got: $out"
  fi
fi
rm -rf "$f"

# --- two documents in one file is not one hooks.json either -----------------
f="$(new_fixture)"
hooks_file "$f" alpha '{"description":"One.","hooks":{}} {"description":"Two.","hooks":{}}'
if run_check "$f" >/dev/null 2>&1; then
  fail "two concatenated documents should fail"
else
  ok "two concatenated documents fail closed"
fi
rm -rf "$f"

# --- the live tree ----------------------------------------------------------
if out="$(cd "$SELF_DIR/.." && bash scripts/check-hooks-description.sh 2>&1)"; then
  ok "the repository's own hooks.json files all carry a description"
else
  fail "the live tree fails the gate: $out"
fi

test_harness::report
