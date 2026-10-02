#!/usr/bin/env bash
# Both implementation worker agents carry the same worker contract inline, so a worker that never
# reads a reference file still gets the scope fence, STOP rules and return shape. This suite fails
# when the text between the contract markers, or the skills: and tools: frontmatter, differs
# between implementer.md and scoped-implementer.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS="$SCRIPT_DIR/../agents"
BEGIN='<!-- contract:begin -->'
END='<!-- contract:end -->'

PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok() {
  echo "PASS: $1"
  PASS=$((PASS + 1))
}
bad() {
  echo "FAIL: $1"
  FAIL=$((FAIL + 1))
}

# contract <file>: the lines strictly between the one begin and one end marker.
contract() {
  awk -v b="$BEGIN" -v e="$END" '$0 == e { on = 0 } on { print } $0 == b { on = 1 }' "$1"
}

# frontmatter_key <file> <key>: the key's line plus its indented continuation lines.
frontmatter_key() {
  awk -v k="$2:" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && on && /^[[:space:]]/ { print; next }
    fm { on = 0 }
    fm && index($0, k) == 1 { on = 1; print }
  ' "$1"
}

# check_pair <a> <b>: print one line per violation; return 1 when any.
check_pair() {
  local a="$1" b="$2" f rc=0 key
  for f in "$a" "$b"; do
    if [[ ! -f "$f" ]]; then
      echo "missing agent: $f"
      rc=1
      continue
    fi
    if [[ "$(grep -cxF "$BEGIN" "$f")" != 1 || "$(grep -cxF "$END" "$f")" != 1 ]]; then
      echo "want exactly one begin and one end marker: $f"
      rc=1
    elif [[ -z "$(contract "$f")" ]]; then
      echo "empty or inverted contract block: $f"
      rc=1
    fi
  done
  [[ "$rc" == 0 ]] || return 1
  if [[ "$(contract "$a")" != "$(contract "$b")" ]]; then
    echo "contract blocks differ"
    rc=1
  fi
  for key in skills tools; do
    if [[ -z "$(frontmatter_key "$a" "$key")" ]]; then
      echo "no $key: frontmatter in $a"
      rc=1
    elif [[ "$(frontmatter_key "$a" "$key")" != "$(frontmatter_key "$b" "$key")" ]]; then
      echo "$key: frontmatter differs"
      rc=1
    fi
  done
  return "$rc"
}

IMPL="$AGENTS/implementer.md"
SCOPED="$AGENTS/scoped-implementer.md"

if out="$(check_pair "$IMPL" "$SCOPED")"; then
  ok "shipped implementer and scoped-implementer carry the same contract, skills and tools"
else
  bad "shipped agents out of sync:"
  printf '%s\n' "$out" | sed 's/^/       /'
fi

# The check must be able to fail. Each case perturbs a copy of the shipped pair.
# perturb <label> <expected substring> <sed expression applied to the scoped copy>
perturb() {
  local dir="$TMP/$1" out
  mkdir -p "$dir"
  cp "$IMPL" "$dir/a.md"
  cp "$SCOPED" "$dir/b.md"
  sed -i "$3" "$dir/b.md"
  if out="$(check_pair "$dir/a.md" "$dir/b.md")"; then
    bad "$1: check passed a perturbed copy"
  elif [[ "$out" == *"$2"* ]]; then
    ok "$1: check reports '$2'"
  else
    bad "$1: wanted '$2', got: $out"
  fi
}

if [[ -f "$IMPL" && -f "$SCOPED" ]]; then
  perturb "edited-contract-line" "contract blocks differ" '/^<!-- contract:begin -->$/,/^<!-- contract:end -->$/s/STOP/stop/'
  perturb "dropped-end-marker" "exactly one begin and one end marker" '/^<!-- contract:end -->$/d'
  perturb "tools-drift" "tools: frontmatter differs" 's/^tools: "Read, /tools: "Read, NotebookEdit, /'
  perturb "skills-drift" "skills: frontmatter differs" 's/^  - testing:test-value$/  - testing:other/'
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" == 0 ]]
