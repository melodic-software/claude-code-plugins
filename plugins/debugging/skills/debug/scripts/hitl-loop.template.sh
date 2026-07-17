#!/usr/bin/env bash
# Human-in-the-loop reproduction loop — TEMPLATE.
# Copy this file, replace the placeholder steps below, and run it yourself.
# The human runs the script in their terminal; paste the captured stdout back to the agent.
#
# Usage (user-run — do NOT invoke via the agent Bash tool; interactive `read` needs a TTY):
#   bash hitl-loop.template.sh
#
# Helpers:
#   step "<instruction>"          → show instruction, wait for Enter
#   capture VAR "<question>"      → show question, read response into VAR
#
# At the end, captured values are printed as KEY=VALUE for the agent to parse
# from the pasted stdout.
#
# Cross-platform notes:
# - Works on Git Bash (Windows MSYS2), macOS bash 3.2+, Linux bash 4+.
# - For PowerShell-only environments, port `read` to `Read-Host` and `printf`
#   to `Write-Host`.

set -euo pipefail

CAPTURED_VARS=()

step() {
  printf '\n>>> %s\n' "$1"
  read -r -p "    [Enter when done] " _
}

capture() {
  local var="$1" question="$2" answer
  printf '\n>>> %s\n' "$question"
  read -r -p "    > " answer
  printf -v "$var" '%s' "$answer"
  CAPTURED_VARS+=("$var")
}

# === REPLACE EVERYTHING BELOW THIS LINE WITH STEPS FOR YOUR BUG ===========
#
# Example shapes (delete and replace):
#
#   step "Open <where the bug occurs>."
#   capture OBSERVED "Did <expected behavior> happen? (y/n)"
#   capture DETAIL "Paste any error message or describe what you saw:"
#
# Each script run should map 1:1 to one trigger of the bug. Keep steps small
# and verifiable — if the human cannot answer the question without
# interpretation, the question is too vague.

step "TODO: replace with the first action the human must take"

capture RESULT "TODO: replace with the question that captures the observation"

# === REPLACE EVERYTHING ABOVE THIS LINE ===================================

printf '\n--- Captured ---\n'
for var in "${CAPTURED_VARS[@]}"; do
  # shellcheck disable=SC2154  # each name in CAPTURED_VARS is set by `capture` when the user instantiates this template.
  printf '%s=%s\n' "$var" "${!var}"
done
