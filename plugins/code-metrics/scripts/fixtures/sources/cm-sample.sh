# shellcheck shell=bash
# Fixture source for the code-metrics suites: a small shell file with one
# function, one branch, a comment, and a blank line, so every counter has
# something to count. Never executed, so it carries no shebang and no exec
# bit; kept lint-clean on purpose.
set -euo pipefail

greet() {
  if [[ -n "${1:-}" ]]; then
    printf 'hello %s\n' "$1"
  else
    printf 'hello\n'
  fi
}

greet "${1:-}"
