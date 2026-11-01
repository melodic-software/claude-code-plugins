#!/usr/bin/env bash
# Black-box contract test for container-label.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
# test-scope: plugins/planning/lib/resolve-convention-home.sh plugins/planning/skills/setup/scripts/yaml-subset.awk
set -uo pipefail
# A fixture never inherits the caller's git environment.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/container-label.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# new_repo <name>: an empty git work tree under $TMP with a default convention home.
new_repo() {
  local dir="$TMP/$1"
  mkdir -p "$dir/docs/conventions"
  git -C "$dir" init -q
  printf '%s\n' "$dir"
}

# expect <label> <want-exit> <want-stdout-prefix> <repo>
expect() {
  local label="$1" want="$2" prefix="$3" repo="$4" out got
  out="$(bash "$SUT" --root "$repo" 2>/dev/null)"
  got=$?
  if [[ "$got" -eq "$want" && "$out" == "$prefix"* ]]; then
    pass "$label"
  else
    fail "$label (want exit $want and '$prefix...', got exit $got and '$out')"
  fi
}

repo="$(new_repo no-file)"
expect "no work-items.yaml -> default" 0 "work-map" "$repo"

repo="$(new_repo no-key)"
printf 'tracker:\n  provider: github\n  config:\n    lease_ttl_hours: 24\n' >"$repo/docs/conventions/work-items.yaml"
expect "binding without the key -> default" 0 "work-map" "$repo"

repo="$(new_repo remap)"
printf 'tracker:\n  provider: github\n  config:\n    lease_ttl_hours: 24\n    container_label: decision-map\n' >"$repo/docs/conventions/work-items.yaml"
expect "remapped label -> the remap" 0 "decision-map" "$repo"

repo="$(new_repo empty)"
printf 'tracker:\n  config:\n    container_label: ""\n' >"$repo/docs/conventions/work-items.yaml"
expect "empty label -> default" 0 "work-map" "$repo"

repo="$(new_repo mapping)"
printf 'tracker:\n  config:\n    container_label:\n      a: b\n' >"$repo/docs/conventions/work-items.yaml"
expect "mapping label -> ERROR" 1 "ERROR:" "$repo"

repo="$(new_repo sequence)"
printf 'tracker:\n  config:\n    container_label: [a, b]\n' >"$repo/docs/conventions/work-items.yaml"
expect "sequence label -> ERROR" 1 "ERROR:" "$repo"

repo="$(new_repo empty-sequence)"
printf 'tracker:\n  config:\n    container_label: []\n' >"$repo/docs/conventions/work-items.yaml"
expect "empty sequence label -> ERROR" 1 "ERROR:" "$repo"

repo="$(new_repo control)"
printf 'tracker:\n  config:\n    container_label: "a\\tb"\n' >"$repo/docs/conventions/work-items.yaml"
expect "label with a control character -> ERROR" 1 "ERROR:" "$repo"

repo="$(new_repo broken-pointer)"
# shellcheck disable=SC2016 # the backticks are the pointer line's literal text.
printf '<!-- BEGIN GENERATED: convention-home -->\nConvention home: `missing/`\n<!-- END GENERATED: convention-home -->\n' >"$repo/AGENTS.md"
expect "broken convention-home pointer -> ERROR" 1 "ERROR:" "$repo"

repo="$(new_repo quote)"
printf 'tracker:\n  config:\n    container_label: "it'"'"'s"\n' >"$repo/docs/conventions/work-items.yaml"
expect "label with a quote -> ERROR" 1 "ERROR:" "$repo"

repo="$(new_repo unparsable)"
printf 'tracker:\n  config: {a: b}\n' >"$repo/docs/conventions/work-items.yaml"
expect "unparsable work-items.yaml -> ERROR" 1 "ERROR:" "$repo"

repo="$(new_repo pointer)"
mkdir -p "$repo/conventions"
# shellcheck disable=SC2016 # the backticks are the pointer line's literal text.
printf '<!-- BEGIN GENERATED: convention-home -->\nConvention home: `conventions/`\n<!-- END GENERATED: convention-home -->\n' >"$repo/AGENTS.md"
printf 'tracker:\n  config:\n    container_label: epic\n' >"$repo/conventions/work-items.yaml"
printf 'tracker:\n  config:\n    container_label: wrong-home\n' >"$repo/docs/conventions/work-items.yaml"
expect "bound home is read, not the default home" 0 "epic" "$repo"

bash "$SUT" --bogus >/dev/null 2>&1
got=$?
if [[ "$got" -eq 2 ]]; then pass "unknown argument -> exit 2"; else fail "unknown argument (want exit 2, got $got)"; fi

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo "all passed"
