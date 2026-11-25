# shellcheck shell=bash

export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

FAILED=0
CASE_NUM=0

real_bash="$(command -v bash)"

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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
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
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}
count_matching() { printf '%s\n' "$1" | grep -cE "$2"; }

make_stub_path() {
  local dir="$1" tool src
  shift
  mkdir -p "$dir"
  for tool in "$@"; do
    src="$(command -v "$tool" 2>/dev/null)" || continue
    printf '#!%s\nexec "%s" "$@"\n' "$real_bash" "$src" >"$dir/$tool"
    chmod +x "$dir/$tool"
  done
}

report_and_exit() {
  if [[ "$FAILED" -eq 0 ]]; then
    printf '\nAll %d checks passed.\n' "$CASE_NUM"
    exit 0
  fi
  printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
}
