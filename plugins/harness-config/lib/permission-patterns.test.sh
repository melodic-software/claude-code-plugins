#!/usr/bin/env bash
# Regression tests for lib/permission-patterns.sh — the auto-mode drop
# vocabulary shared by audit-permission-grants' check P1 and
# audit-permission-state's entry diff.
#
# The classification behavior is exercised in depth by the P1 detector's own
# suite. What is proved HERE is what only a second consumer needs: the file is
# safe to source, and its bodies are usable standalone without the detector.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/permission-patterns.sh"

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

# --- Side-effect freedom -----------------------------------------------------
rc=0
bash -n "$LIB" || rc=$?
assert_eq "parses under bash -n" "0" "$rc"

out=$(bash -c "source '$LIB' >/dev/null 2>&1; echo SURVIVED" 2>&1)
assert_eq "sourcing does not exit the caller" "SURVIVED" "$out"
noise=$(bash -c "source '$LIB'" 2>&1)
assert_eq "sourcing writes nothing to stdout or stderr" "" "$noise"

# --- The vocabulary is defined and usable standalone -------------------------
# shellcheck source=permission-patterns.sh
source "$LIB"
assert_eq "P1 body defined" "0" "$([[ -n "${CCPERM_P1_ERE:-}" ]] && echo 0 || echo 1)"
assert_eq "tool-token body defined" "0" "$([[ -n "${CCPERM_TOOL_TOKEN_ERE:-}" ]] && echo 0 || echo 1)"

matches() { grep -qE "$CCPERM_P1_ERE" <<<"$1" && echo yes || echo no; }

# One rule per documented drop class, and one narrow rule that must carry over.
assert_eq "blanket Bash(*) is a drop class" "yes" "$(matches 'Bash(*)')"
assert_eq "wildcarded interpreter is a drop class" "yes" "$(matches 'Bash(python*)')"
assert_eq "package-manager runner is a drop class" "yes" "$(matches 'Bash(npx *)')"
assert_eq "script-glob interpreter is a drop class" "yes" "$(matches 'Bash(*.py:*)')"
assert_eq "narrow rule carries over" "no" "$(matches 'Bash(npm test)')"
assert_eq "bare-name command rule carries over" "no" "$(matches 'Bash(node-gyp:*)')"
assert_eq "path-prefixed runner is a drop class" "yes" "$(matches 'Bash(/usr/bin/npm run:*)')"
assert_eq "narrow path-prefixed runner carries over" "no" "$(matches 'Bash(/usr/bin/npm test)')"
assert_eq "version-suffixed runner is a drop class" "yes" "$(matches 'Bash(pnpm@9 dlx *)')"
assert_eq "narrow version-suffixed runner carries over" "no" "$(matches 'Bash(pnpm@9 install)')"
assert_eq "a hyphenated path-prefixed command is not a runner" "no" \
  "$(matches 'Bash(node_modules/.bin/npm-check:*)')"
assert_eq "wrapper followed only by a wildcard is a drop class" "yes" "$(matches 'Bash(timeout *)')"
assert_eq "wrapper with a fixed command carries over" "no" "$(matches 'Bash(timeout 30 git status)')"
assert_eq "a wrapper-led wildcard after an argument is not the wrapper class" "no" \
  "$(grep -qE "$CCPERM_P1_WRAPPER_ERE" <<<'Bash(timeout 30 *)' && echo yes || echo no)"
assert_eq "leading-wildcard shell rule is a drop class" "yes" "$(matches 'Bash(* --version)')"
assert_eq "a mid-command wildcard carries over" "no" "$(matches 'Bash(git log *)')"
assert_eq "\$HOME-led wildcard path is a drop class" "yes" "$(matches "Bash(\$HOME/bin/*)")"
assert_eq "exact \$HOME path carries over" "no" "$(matches "Bash(\$HOME/bin/deploy.sh)")"
assert_eq "a longer variable name is not \$HOME" "no" "$(matches "Bash(\$HOMEBREW_PREFIX/bin/x *)")"
assert_eq "Windows backslash program with a wildcard is a drop class" "yes" \
  "$(matches 'PowerShell(C:\tools\x.exe *)')"
assert_eq "exact Windows backslash program carries over" "no" "$(matches 'PowerShell(C:\tools\x.exe -v)')"
assert_eq "a .\\ script path with a wildcard carries over" "no" \
  "$(matches 'PowerShell(.\tools\x.ps1 *)')"
assert_eq "a YAML-escaped quoted bundled path is not a Windows path" "no" \
  "$(matches "Bash(\\\"\${CLAUDE_SKILL_DIR}/x.sh\\\":*)")"

# The token grammar keeps a tool name inside another rule's payload from
# surfacing as its own token — the property whole-tool detection depends on.
tokens=$(printf '%s\n' 'Bash(echo Agent)' | grep -oE "$CCPERM_TOOL_TOKEN_ERE")
assert_eq "payload text is not a separate top-level token" "Bash(echo Agent)" "$tokens"

paren_path=$(printf '%s\n' 'Edit(./Finance (2024)/**)' | grep -oE "$CCPERM_TOOL_TOKEN_ERE")
assert_eq "a path parenthesis stays inside one token" "Edit(./Finance (2024)/**)" "$paren_path"

trailing=$(printf '%s\n' 'Bash(ls) x' | grep -oE "$CCPERM_TOOL_TOKEN_ERE" | head -n 1)
assert_eq "the specifier token stops before trailing text" "Bash(ls)" "$trailing"

assert_eq "an interpreter wildcard with a parenthesized argument still drops" "yes" \
  "$(matches 'Bash(python (x) *)')"

report_and_exit
