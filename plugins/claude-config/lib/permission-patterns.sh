# shellcheck shell=bash
# The bodies are consumed by the sourcing drivers, never in this file itself —
# SC2034 "appears unused" is a false positive for a define-only library.
# shellcheck disable=SC2034
# Claude Code auto-mode drop vocabulary — shared regex BODIES, define-only.
#
# No functions, no env reads, no I/O, no exit calls. A driver sources this file
# and adds its own wrapping: which surfaces it scans, how it labels a finding,
# severity, and exit-code mapping stay driver-owned.
#
# WHY THIS EXISTS: two components need the same answer to "which allow rules does
# Claude Code drop on entering auto mode" — `audit-permission-grants` check P1,
# which flags them as fragile grants, and `audit-permission-state`, which renders
# the before/after entry diff. A second copy of these alternations would drift the
# moment one side learned a new interpreter or runner.
#
# POSIX ERE only (grep -E) — NO grep -P: macOS BSD grep lacks it entirely, and
# bash =~ delegates to the platform regex library, so non-POSIX extensions would
# not behave identically on Linux CI and Git Bash.
#
# DEFINE single-quoted where the body carries backslashes, EXPAND double-quoted
# ("$CCPERM_…"): a double-quoted definition would collapse the escapes and
# silently change what grep matches.

# The rule classes upstream documents as dropped on entering auto mode: blanket
# `Bash(*)`/`PowerShell(*)`, wildcarded interpreters, package-manager run
# commands, and all `Agent` allow rules. Narrow rules such as `Bash(npm test)`
# carry over and must never match.
#
# python accepts version suffixes (python3, python3.11, python2.7): pinned
# minor-version binaries are the same interpreter-led grant shape.
CCPERM_INTERP_BODY='python[0-9.]*|node|deno|bun|ruby|perl|php|bash|sh|zsh|pwsh|osascript|Rscript'
CCPERM_RUNNER_BODY='npx|bunx|uvx|pnpm dlx|yarn dlx|pipx run|uv run|npm|pnpm|yarn'
CCPERM_SCRIPT_BODY='py|sh|rb|js|ts|mjs|cjs|pl|php'

# One ERE, case-sensitive on the tool name. Each alternative requires a wildcard
# so an exact narrow rule (Bash(npm test)) never matches:
#   1. blanket Bash(*) / PowerShell(*)
#   2. an interpreter at the command position followed (eventually) by a * —
#      the interpreter may carry a path prefix (Bash(.venv/bin/python *),
#      Bash(/usr/bin/python3 *)): a wildcarded interpreter-led grant is the
#      same arbitrary-code shape regardless of how the interpreter is addressed.
#      What follows the name must be a * or a real separator (space, quote, :)
#      so a hyphenated bare PATH command that merely starts with an interpreter
#      or runner name (Bash(node-gyp:*), Bash(npm-check-updates:*)) — the very
#      shape the convention recommends — is not flagged
#   3. a package-manager run/exec command followed by a * — both the run/exec
#      subcommand forms (npx, pnpm dlx, uv run, …) and a bare package manager
#      wildcard (Bash(npm:*), Bash(npm *)), which grants arbitrary execution
#      via npm exec / lifecycle scripts. A bare package-manager name subsumes
#      its own run wildcard (npm matches `npm run *`), so `npm run` etc. are not
#      listed separately. A fixed subcommand (Bash(npm test), Bash(npm run
#      build)) carries no * and is not matched.
#   4. a leading-glob command that resolves to a script (Bash(*.py:*))
#
# Each alternative captures the whole Tool(...) spec (trailing [^)]*\) ) so a
# driver reports the full offending rule, not a substring truncated at the *.
#
# The four alternatives are also exposed individually so a driver that must NAME
# the class a rule fell into (the entry diff's drop reason) tests them one at a
# time instead of re-deriving the wrapping; the union stays the P1 detector's
# single match target and is composed from them, never written twice.
#
# In the RUNNER alternative, the `([\"' :])` before the `\*` requires a
# separator, so `Bash(npmx *)` does not match the `npm` runner.
CCPERM_P1_BLANKET_ERE="(Bash|PowerShell)\\(\\*\\)"
CCPERM_P1_INTERP_ERE="(Bash|PowerShell)\\([\"' ]*([^)\"' ]*[/\\\\])?(${CCPERM_INTERP_BODY})([\"' :][^)]*)?\\*[^)]*\\)"
CCPERM_P1_RUNNER_ERE="(Bash|PowerShell)\\([\"' ]*(${CCPERM_RUNNER_BODY})([\"' :][^)]*)?([\"' :])\\*[^)]*\\)"
CCPERM_P1_SCRIPTGLOB_ERE="(Bash|PowerShell)\\([\"' ]*\\*[^)]*\\.(${CCPERM_SCRIPT_BODY})[^)]*\\)"
CCPERM_P1_ERE="${CCPERM_P1_BLANKET_ERE}|${CCPERM_P1_INTERP_ERE}|${CCPERM_P1_RUNNER_ERE}|${CCPERM_P1_SCRIPTGLOB_ERE}"

# Splits rule text into top-level `Tool` / `Tool(...)` tokens. The greedy
# `(\(...\))?` consumes a tool's whole parenthesized payload as one token, so a
# tool name inside another rule's payload (e.g. Bash(echo Agent), Bash(grep
# PowerShell *)) never surfaces as its own token. The payload accepts one level
# of nested parentheses (Bash(echo $(date) Agent), Bash(node -e "log()"
# PowerShell)) so an inner `)` does not end the token early; ERE cannot balance
# arbitrary depth, and rule payloads realistically nest at most once.
#
# Drivers use this to tell a whole-tool grant (bare `Bash`, bare or scoped
# `Agent`) from a scoped rule that merely mentions a tool name in its payload.
CCPERM_TOOL_TOKEN_ERE='[A-Za-z_][A-Za-z0-9_]*(\(([^()]|\([^()]*\))*\))?'
