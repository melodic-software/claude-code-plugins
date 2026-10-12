#!/usr/bin/env bash
# Template for a reproduction loop that a person drives by hand.
#
# Copy it, swap the example prompts at the bottom for the steps of your bug,
# and give the copy to the user. The user runs it in their own terminal:
#   bash hitl-loop.template.sh
# The agent's Bash tool cannot run it, because `read` waits on a TTY.
#
# Two prompt helpers:
#   instruct "<what to do>"          print the instruction, wait for Enter
#   ask NAME "<what to report>"      print the question, store the reply in NAME
#
# After the last prompt the script prints a "=== results ===" block with one
# NAME=value line per answer. The user pastes that block back into the session.
#
# Shells: Git Bash on Windows, bash 3.2 or later on macOS, bash 4 or later on
# Linux. A PowerShell-only machine needs a port (Read-Host for `read`,
# Write-Host for `printf`).

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

# ---- Steps for this bug: replace from here --------------------------------
#
# One run of the script is one attempt to trigger the bug. Ask questions a
# person can answer by looking (yes/no, a number, copied text), not ones that
# need judgment to answer. For example:
#
#   instruct "In the mobile app, pick the 25 MB test photo and tap Upload."
#   ask UPLOAD_SECONDS "How many seconds passed before the app showed an error or the photo?"
#   ask ERROR_TEXT "Copy the error message, or type none:"

instruct "TODO: first thing the user does"

ask RESULT "TODO: question whose answer records what the user saw"

# ---- Steps for this bug: replace up to here -------------------------------

printf '\n=== results ===\n'
for name in "${ANSWER_NAMES[@]}"; do
  # shellcheck disable=SC2154  # every name in ANSWER_NAMES was assigned by ask().
  printf '%s=%s\n' "$name" "${!name}"
done
