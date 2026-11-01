#!/usr/bin/env bash
# Check that every tracked test that creates a temp path also removes it on every
# exit path: a *.test.sh that uses mktemp installs a `trap ... EXIT`, and a
# *.test.mjs/js/cjs that makes a folder under os.tmpdir() registers its removal.
#
#   scripts/check-test-tmp-cleanup.sh          discover: list every offender
#   scripts/check-test-tmp-cleanup.sh --check  same, explicit form matching the
#                                              sibling gates (exit 1 on any offender)
#
# The rule: a suite whose non-comment lines mention `mktemp` and none of whose
# non-comment lines match `trap ... EXIT` leaves its fixtures behind on every
# run, and on an early exit or a failed assertion. Any offender is a fail: fix
# a suite by adding the trap. The match is lexical: `trap ... EXIT` inside a
# string a suite runs in a child shell also counts, so a passing suite still
# needs its own trap.
#
# A JS suite offends when a non-comment line passes os.tmpdir() to mkdtemp or
# mkdtempSync and the file never registers a removal that runs on failure too:
# an after/afterAll/afterEach/onTestFinished/t.after hook, a finally block, or a
# process exit handler. tempDir from lib/test-tmp.mjs needs none of these, but
# importing it does not cover a bare call in the same file. A folder whose only
# handle is the join(mkdtempSync(...), "file") expression can never be removed
# by name, so that shape offends whatever else the file does. Both are lexical:
# a file with a hook still has to remove every folder in it.
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one finding per line on stderr, the clean-run statement on
# stdout. Exit: 0 clean, 1 any offender, 2 environment or usage (git or awk
# missing, bad argument).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

for tool in git awk; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'check-test-tmp-cleanup: %s is required\n' "$tool" >&2
    exit 2
  fi
done

# offends <file>: true when the file mentions mktemp and has no EXIT trap,
# ignoring comment lines. fixture_tree::build installs its own EXIT trap that
# removes every tree it built (scripts/lib/fixture-tree.sh), so it counts.
offends() {
  awk '
    /^[[:space:]]*#/ { next }
    /mktemp/ { made = 1 }
    /trap[^#]*EXIT/ { trapped = 1 }
    /fixture_tree::build/ { trapped = 1 }
    END { exit !(made && !trapped) }
  ' "$1"
}

# offends_js <file>: see the header.
offends_js() {
  awk '
    /^[[:space:]]*(\/\/|\*|\/\*)/ { next }
    /mkdtemp(Sync)?\(/ && /tmpdir\(\)/ { made = 1 }
    /join\([[:space:]]*(fs\.)?mkdtemp(Sync)?\([^)]*tmpdir/ { unbound = 1 }
    /(^|[^A-Za-z0-9_])(after|afterAll|afterEach|onTestFinished)\(/ { removed = 1 }
    /finally[[:space:]]*\{/ { removed = 1 }
    /process\.on\(["'"'"']exit/ { removed = 1 }
    END { exit !((made && !removed) || unbound) }
  ' "$1"
}

findings=()
tracked=()
while IFS= read -r -d '' path; do
  tracked+=("$path")
  # shellcheck disable=SC2310  # offends only tests; nothing inside can fail the script
  if offends "$path"; then
    findings+=("$path: mktemp without a trap ... EXIT; add the trap")
  fi
done < <(git ls-files -z -- '*.test.sh')
js_tracked=0
while IFS= read -r -d '' path; do
  js_tracked=$((js_tracked + 1))
  # shellcheck disable=SC2310  # offends_js only tests; nothing inside can fail the script
  if offends_js "$path"; then
    findings+=("$path: a folder under os.tmpdir() with no removal that runs on failure, or never bound to a name; use tempDir from lib/test-tmp.mjs")
  fi
done < <(git ls-files -z -- '*.test.mjs' '*.test.js' '*.test.cjs')

if ((${#findings[@]} == 0)); then
  printf 'check-test-tmp-cleanup: %d tracked *.test.sh and %d JS tests checked; every temp-folder user removes it.\n' "${#tracked[@]}" "$js_tracked"
  exit 0
fi

printf '%s\n' "${findings[@]}" | sort -u >&2
printf 'check-test-tmp-cleanup: %d finding(s); see the header of scripts/%s.\n' "${#findings[@]}" "${0##*/}" >&2
exit 1
