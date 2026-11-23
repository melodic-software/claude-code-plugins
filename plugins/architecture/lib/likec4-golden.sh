#!/usr/bin/env bash

LIKEC4_VERSION="1.59.4"
LIKEC4_GOLDEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/likec4-golden"

likec4_block() {
  awk '/^```likec4$/ { f = 1; next } /^```$/ { f = 0 } f' "$1"
}

assert_likec4_golden() {
  local name="$1" got file="$LIKEC4_GOLDEN_DIR/$1"
  got="$(likec4_block "$2")"
  if [[ -z "$got" ]]; then
    fail "golden $name: a likec4 block" "no fenced likec4 block in $2"
    return
  fi
  if [[ -n "${UPDATE_GOLDEN:-}" ]]; then
    mkdir -p "$LIKEC4_GOLDEN_DIR"
    printf '%s\n' "$got" >"$file"
  fi
  if [[ ! -f "$file" ]]; then
    fail "golden $name: file exists" "$file is missing; run with UPDATE_GOLDEN=1"
  elif [[ "$got" == "$(cat "$file")" ]]; then
    pass "golden $name: block equals the golden file"
  else
    fail "golden $name: block equals the golden file" "$(diff <(printf '%s\n' "$got") "$file")"
  fi
  if [[ -n "${LIKEC4_VALIDATE:-}" ]]; then
    validate_likec4_golden "$name"
  fi
}

validate_likec4_golden() {
  local name="$1" work rc
  work="$(mktemp -d)"
  cp "$LIKEC4_GOLDEN_DIR/$name" "$work/model.c4"
  npx --yes "likec4@$LIKEC4_VERSION" validate "$work" >"$work/out" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    pass "golden $name: likec4 $LIKEC4_VERSION validate exits 0"
  else
    fail "golden $name: likec4 $LIKEC4_VERSION validate exits 0" "exit $rc: $(cat "$work/out")"
  fi
  rm -rf "$work"
}
