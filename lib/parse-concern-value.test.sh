#!/usr/bin/env bash
# Regression tests for lib/parse-concern-value.sh — the shared topic-docs
# concern-value parser. Run directly: bash lib/parse-concern-value.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/parse-concern-value.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

# Write a concern file holding a single memory_dir line, then resolve it.
resolve() {
  local content="$1" key="${2:-memory_dir}" fallback="${3:-}"
  local f="$TEST_TMPDIR/topic-docs.yaml"
  printf '%s\n' "$content" >"$f"
  bash "$SCRIPT" "$f" "$key" "$fallback"
}

# --- Case: --help exits 0 with usage ---
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Regression 1: `#` inside a quoted value is preserved (the reported bug) ---
assert_eq 'double-quoted a#b keeps the #' "a#b" "$(resolve 'memory_dir: "a#b"')"
assert_eq 'single-quoted a#b keeps the #' "a#b" "$(resolve "memory_dir: 'a#b'")"
assert_eq 'unquoted .work/#topic keeps the #' ".work/#topic" "$(resolve 'memory_dir: .work/#topic')"
assert_eq 'quoted value with trailing comment drops comment, keeps inner #' \
  "a#b" "$(resolve 'memory_dir: "a#b"  # inline comment')"

# --- Regression 2: valid YAML key spacing must not read as "key absent" ---
# Reading a declared key as absent silently substitutes the caller's fallback
# for a value the repo really chose.
assert_eq 'space before the colon resolves' ".scratch" "$(resolve 'memory_dir : .scratch')"
assert_eq 'indented root mapping resolves' ".scratch" "$(resolve '  memory_dir: .scratch')"
assert_eq 'tab-indented key resolves' ".scratch" "$(resolve "$(printf '\tmemory_dir: .scratch')")"
assert_eq 'space before colon does not defeat the fallback path' \
  ".notes" "$(resolve 'memory_dir :' memory_dir '.notes')"
# A same-named key nested under another mapping is a DIFFERENT key.
assert_eq 'root key wins over a nested one' "top" \
  "$(resolve "$(printf 'other:\n  memory_dir: nested\nmemory_dir: top')")"
assert_eq 'a nested key never answers for an empty root key' ".notes" \
  "$(resolve "$(printf 'other:\n  memory_dir: nested\nmemory_dir:')" memory_dir '.notes')"
assert_eq 'a nested key never answers for an absent root key' ".notes" \
  "$(resolve "$(printf 'other:\n  memory_dir: nested\n')" memory_dir '.notes')"
assert_eq 'a key deeper than an indented root mapping is still nested' ".notes" \
  "$(resolve "$(printf '  other:\n    memory_dir: nested\n  contract_dir: docs/x')" memory_dir '.notes')"
assert_eq 'a leading document marker does not become the base indent' ".scratch" \
  "$(resolve "$(printf -- '---\nmemory_dir: .scratch')")"
# A key that only appears as a SUBSTRING of another key must not match.
assert_eq 'a longer key is not matched by a shorter one' \
  ".notes" "$(resolve 'memory_dir_extra: .scratch' memory_dir '.notes')"

# --- Held behavior: unquoted trailing ` # comment` still stripped ---
assert_eq 'unquoted trailing comment stripped' ".scratch" "$(resolve 'memory_dir: .scratch  # the tier')"

# --- Held behavior: surrounding whitespace trimmed ---
assert_eq 'leading/trailing whitespace trimmed (unquoted)' ".scratch" "$(resolve 'memory_dir:    .scratch   ')"

# --- Held behavior: interior whitespace in a quoted value preserved ---
assert_eq 'quoted interior space preserved' ".scratch dir" "$(resolve 'memory_dir: ".scratch dir"')"

# --- Held behavior: trailing slash normalized ---
assert_eq 'trailing slash normalized (unquoted)' ".work" "$(resolve 'memory_dir: .work/')"
assert_eq 'trailing slash normalized (quoted)' "foo/bar" "$(resolve 'memory_dir: "foo/bar/"')"

# --- Regression 2: absent/empty key falls back to the caller-supplied location ---
assert_eq 'absent key returns fallback (declared save-point)' \
  ".notes" "$(resolve 'other_key: x' memory_dir '.notes')"
assert_eq 'empty value returns fallback' \
  ".notes" "$(resolve 'memory_dir:' memory_dir '.notes')"
assert_eq 'comment-only value falls back (memory_dir: # use default)' \
  ".notes" "$(resolve 'memory_dir: # use default' memory_dir '.notes')"
assert_eq 'comment-only value, no fallback => empty' \
  "" "$(resolve 'memory_dir: # use default')"
assert_eq 'fallback is trailing-slash-agnostic passthrough' \
  ".notes/deep" "$(resolve 'other_key: x' memory_dir '.notes/deep')"

# --- Absent concern FILE returns fallback (empty when none) ---
assert_eq 'missing file, no fallback => empty' "" "$(bash "$SCRIPT" "$TEST_TMPDIR/nope.yaml" memory_dir)"
assert_eq 'missing file, with fallback => fallback' ".x" "$(bash "$SCRIPT" "$TEST_TMPDIR/nope.yaml" memory_dir '.x')"

# --- Present key wins over fallback ---
assert_eq 'present key overrides fallback' ".real" "$(resolve 'memory_dir: .real' memory_dir '.fallback')"

# --- Nothing resolves => empty (caller applies documented default) ---
assert_eq 'no key, no fallback => empty' "" "$(resolve 'other_key: x')"

# --- Missing args exit 2 ---
rc=0
bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
assert_exit "no args exits 2" 2 "$rc"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
