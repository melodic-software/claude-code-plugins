#!/usr/bin/env bash
# parity-check.sh: prove a scanner change preserves findings.
#
# Runs the scanner at a base ref (default: the merge base with origin/main,
# extracted with git archive into .work/) and the working-tree scanner over
# the same roots, under every awk on PATH among gawk and mawk, and diffs their
# output and exit codes. Roots: each evals/fixtures subdirectory, then this
# repository's whole tree.
#
# Each run must examine more than 0 files (test files plus Playwright configs)
# and exit 0 or 1, or the diff proves nothing. It also diffs the resolved
# regex strings of both engines per language, because the fixtures do not
# exercise every alternative of every regex.
#
# Usage: parity-check.sh [<base-ref>]
# Exit: 0 parity holds; 1 a diff or a vacuous run; 2 setup failed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)" || exit 2
REL_SCRIPTS="plugins/testing/skills/audit/scripts"
FIX="$SCRIPT_DIR/../evals/fixtures"

base="${1:-$(git -C "$REPO" merge-base HEAD origin/main)}" || exit 2
[[ -n "$base" ]] || {
  echo "ERROR: no base ref" >&2
  exit 2
}

mkdir -p "$REPO/.work"
WORK="$(mktemp -d "$REPO/.work/parity-check.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

paths=("$REL_SCRIPTS")
git -C "$REPO" cat-file -e "$base:plugins/testing/skills/audit/adapters" 2>/dev/null &&
  paths+=("plugins/testing/skills/audit/adapters")
git -C "$REPO" archive "$base" "${paths[@]}" | tar -x -C "$WORK" || {
  echo "ERROR: cannot extract $REL_SCRIPTS at $base" >&2
  exit 2
}
BASE_SCAN="$WORK/$REL_SCRIPTS/cant-fail-scan.sh"
NEW_SCAN="$SCRIPT_DIR/cant-fail-scan.sh"

# Prints each engine regex as NAME=value for one language, from whichever
# variable names the engine uses (the pre-adapter *_ERE literals, or the
# adapter-driven names), so the two sides are compared field by field.
cat >"$WORK/dump.awk" <<'EOF'
function pick(a, b) { return a != "" ? a : b }
BEGIN {
  printf "ANY=%s\n", pick(ANY_ERE, R_ANY)
  printf "MOCKA=%s\n", pick(MOCKA_ERE, R_MOCKA)
  printf "MOCKC=%s\n", pick(MOCKC_ERE, R_MOCKC)
  printf "STRIP=%s\n", pick(STRIP_ERE, R_STRIP)
  printf "START=%s\n", pick(pick(TEST_START_ERE, ATTR_ERE), R_START)
  printf "SKIP=%s\n", pick(pick(pick(TEST_SKIP_ERE, SKIP_DECOR_ERE), ATTR_SKIP_ERE), R_SKIP)
  printf "SUITE_SKIP=%s\n", pick(SUITE_SKIP_ERE, R_SUITE_SKIP)
  printf "EXEMPT=%s\n", pick(EXEMPT_ERE, R_EXEMPT)
  printf "EQ_CALL2=%s\n", pick(TAUT_FUNCS, R_CALL2)
  exit
}
EOF

# dump_engine <scripts-dir> <lang> <out>: the pre-adapter engine takes
# LANG_ID; the adapter engine takes an adapter id and the loaded table.
dump_engine() {
  local dir="$1" lang="$2" out="$3" id table
  if [[ -r "$dir/adapter-load.awk" ]]; then
    case "$lang" in
    js) id=js-jest ;;
    py) id=py-pytest ;;
    cs) id=cs-xunit ;;
    esac
    table="$WORK/table.$$"
    awk -f "$dir/adapter-load.awk" "$dir"/../adapters/*.yaml >"$table" || return 2
    awk -v ADAPTER="$id" -v ADAPTER_TABLE="$table" -f "$dir/mask-js.awk" \
      -f "$dir/cant-fail-scan.awk" -f "$WORK/dump.awk" /dev/null >"$out"
  else
    awk -v LANG_ID="$lang" -f "$dir/mask-js.awk" -f "$dir/cant-fail-scan.awk" \
      -f "$WORK/dump.awk" /dev/null >"$out"
  fi
}

failed=0
legs=0
for bin in gawk mawk; do
  path_bin="$(command -v "$bin")" || continue
  shim="$WORK/shim-$bin"
  mkdir -p "$shim"
  ln -sf "$path_bin" "$shim/awk"
  version="$(PATH="$shim:$PATH" awk -W version 2>&1 | head -1)"
  case "$bin:$version" in
  gawk:GNU\ Awk*) ;;
  mawk:mawk*) ;;
  *)
    echo "ERROR: $bin shim resolved to: $version" >&2
    exit 2
    ;;
  esac
  legs=$((legs + 1))

  for lang in js py cs; do
    PATH="$shim:$PATH" dump_engine "$WORK/$REL_SCRIPTS" "$lang" "$WORK/re.base" || true
    PATH="$shim:$PATH" dump_engine "$SCRIPT_DIR" "$lang" "$WORK/re.new" || true
    if diff -u "$WORK/re.base" "$WORK/re.new" >"$WORK/re.diff"; then
      echo "PASS [$bin] regex parity: $lang"
    else
      failed=$((failed + 1))
      echo "FAIL [$bin] regex parity: $lang"
      cat "$WORK/re.diff"
    fi
  done

  for root in "$FIX"/config "$FIX"/exempt "$FIX"/mock-only "$FIX"/negative \
    "$FIX"/positive "$FIX"/sanity "$REPO"; do
    label="fixtures/${root##*/}"
    [[ "$root" == "$REPO" ]] && label="(repo tree)"
    rc_base=0
    rc_new=0
    CANT_FAIL_SCAN_ROOT="$root" PATH="$shim:$PATH" bash "$BASE_SCAN" >"$WORK/out.base" 2>&1 || rc_base=$?
    CANT_FAIL_SCAN_ROOT="$root" PATH="$shim:$PATH" bash "$NEW_SCAN" >"$WORK/out.new" 2>&1 || rc_new=$?
    examined="$(awk '/^  test files: /{t=$3} /^  playwright configs: [0-9]+ examined/{c=$3} END{print t+c}' "$WORK/out.new")"
    if [[ "$examined" -le 0 ]]; then
      failed=$((failed + 1))
      echo "FAIL [$bin] $label: examined=0 (vacuous run)"
    elif [[ "$rc_new" -gt 1 || "$rc_base" -gt 1 ]]; then
      failed=$((failed + 1))
      echo "FAIL [$bin] $label: exit base=$rc_base new=$rc_new (want 0 or 1)"
      tail -5 "$WORK/out.new"
    elif [[ "$rc_base" -ne "$rc_new" ]] || ! diff -u "$WORK/out.base" "$WORK/out.new" >"$WORK/out.diff"; then
      failed=$((failed + 1))
      echo "FAIL [$bin] $label: output or exit differs (base=$rc_base new=$rc_new)"
      head -40 "$WORK/out.diff"
    else
      echo "PASS [$bin] $label: examined>0 ($examined), exit $rc_new, output identical"
    fi
  done
done

if [[ "$legs" -eq 0 ]]; then
  echo "ERROR: neither gawk nor mawk on PATH" >&2
  exit 2
fi
[[ "$failed" -eq 0 ]] || {
  echo "parity FAILED: $failed check(s)"
  exit 1
}
echo "parity holds against $base under $legs awk(s)"
