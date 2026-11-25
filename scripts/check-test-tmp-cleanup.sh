#!/usr/bin/env bash
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

offends() {
  awk '
    /^[[:space:]]*#/ { next }
    /mktemp/ { made = 1 }
    /trap[^#]*EXIT/ { trapped = 1 }
    /fixture_tree::build/ { trapped = 1 }
    END { exit !(made && !trapped) }
  ' "$1"
}

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
sh_tracked=0
while IFS= read -r -d '' path; do
  sh_tracked=$((sh_tracked + 1))
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
  printf 'check-test-tmp-cleanup: %d tracked *.test.sh and %d JS tests checked; every temp-folder user removes it.\n' "$sh_tracked" "$js_tracked"
  exit 0
fi

printf '%s\n' "${findings[@]}" | sort -u >&2
printf 'check-test-tmp-cleanup: %d finding(s); see the header of scripts/%s.\n' "${#findings[@]}" "${0##*/}" >&2
exit 1
