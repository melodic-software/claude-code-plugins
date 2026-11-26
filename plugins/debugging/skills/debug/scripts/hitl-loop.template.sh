#!/usr/bin/env bash
set -euo pipefail

ANSWER_NAMES=()

instruct() {
  printf '\n* %s\n' "$1"
  read -r -p "  press Enter when done " _
}

ask() {
  local name="$1" prompt="$2" reply
  printf '\n? %s\n' "$prompt"
  read -r -p "  answer: " reply
  printf -v "$name" '%s' "$reply"
  ANSWER_NAMES+=("$name")
}

instruct "TODO: first thing the user does"

ask RESULT "TODO: question whose answer records what the user saw"

printf '\n=== results ===\n'
for name in "${ANSWER_NAMES[@]}"; do
  # shellcheck disable=SC2154  # every name in ANSWER_NAMES was assigned by ask().
  printf '%s=%s\n' "$name" "${!name}"
done
