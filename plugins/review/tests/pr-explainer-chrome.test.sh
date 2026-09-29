#!/usr/bin/env bash
# The pr-explainer builder inlines the rendered-views chrome tokens. This test
# fails, naming the token, when an inlined value drifts from the reference.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="$PLUGIN_DIR/skills/pr-explainer/scripts/build-explainer.mjs"
CHROME="$PLUGIN_DIR/../visualization/reference/html-chrome.html"

if [[ ! -f "$CHROME" ]]; then
  echo "skip: $CHROME absent (a plugin cache does not carry the visualization plugin)"
  exit 0
fi

FAIL=0

# value NAME FILE [dark]: the lowercased value of the first (or, with dark,
# the second) '--NAME: value;' declaration, whitespace removed.
value() {
  local n
  if [[ "${3:-}" == dark ]]; then n=2; else n=1; fi
  grep -oE -- "--$1:[^;]+;" "$2" | sed -n "${n}p" | sed -E 's/^[^:]+:[[:space:]]*//; s/;$//' | tr '[:upper:]' '[:lower:]'
}

check() { # label expected actual
  if [[ -n "$2" && "$2" == "$3" ]]; then
    echo "ok: $1 = $2"
  else
    echo "FAIL: $1: reference '$2', builder '$3'" >&2
    FAIL=$((FAIL + 1))
  fi
}

for t in ivory slate clay-deep gray-300 gray-500; do
  check "--$t" "$(value "$t" "$CHROME")" "$(value "$t" "$BUILDER")"
done

# Dark-mode --focus is the reference's clay-soft; the builder holds the literal.
check "dark --focus" "$(value clay-soft "$CHROME")" "$(value focus "$BUILDER" dark)"

# Focus rule: same declarations as the reference's focus-visible rule.
rule() { tr '\n' ' ' <"$1" | grep -oE 'a:focus-visible[^}]*\}' | head -n1 | tr -s '[:space:]' ' ' | sed 's/ *}/ }/; s/; }/;}/'; }
check "focus rule" "$(rule "$CHROME")" "$(rule "$BUILDER")"

exit "$((FAIL > 0))"
