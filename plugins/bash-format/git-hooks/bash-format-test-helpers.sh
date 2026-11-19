# shellcheck shell=bash
# shellcheck disable=SC2153,SC2154 # CHECK, WORK, REPO and SHEBANG come from the sourcing suite

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

check() {
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

merge_repo() {
  new_repo
  git -C "$REPO" checkout -q -b side
  printf '%s\nif true; then\n\tcd /tmp\nfi\n' "$SHEBANG" >"$REPO/x.sh"
  git -C "$REPO" add x.sh
  git -C "$REPO" commit -q -m side --no-verify
  git -C "$REPO" checkout -q main
  printf '%s\necho main\n' "$SHEBANG" >"$REPO/main.sh"
  git -C "$REPO" add main.sh
  git -C "$REPO" commit -q -m main --no-verify
  git -C "$REPO" merge -q --no-commit side >/dev/null 2>&1
}
