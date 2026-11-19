# shellcheck shell=bash
# shellcheck disable=SC2154 # CHECK, WORK and SETTINGS_BODY come from the sourcing suite

PASS=0
FAIL=0
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

n=0
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  if [[ "${1:-}" != NONE ]]; then
    printf '%s\n' "$SETTINGS_BODY" >"$REPO/PSScriptAnalyzerSettings.psd1"
  fi
  printf 'Get-ChildItem .\n' >"$REPO/seed.ps1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
}

check() {
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}
