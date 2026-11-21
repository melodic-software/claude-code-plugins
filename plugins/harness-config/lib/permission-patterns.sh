# shellcheck shell=bash
# The sourcing drivers read these bodies, so SC2034 "appears unused" is a false
# positive here.
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

# The rule classes upstream documents as dropped on entering auto mode, eight in
# all (https://code.claude.com/docs/en/permission-modes#how-auto-mode-evaluates-actions,
# read 2026-11-21): blanket `Bash(*)`/`PowerShell(*)`, wildcarded interpreters,
# a process wrapper followed only by a wildcard (`Bash(timeout *)`), shell rules
# that start with a wildcard (`Bash(* --version)`), some wildcarded paths
# (`Bash($HOME/bin/*)`, `PowerShell(C:\tools\x.exe *)`), package-manager run
# commands, all `Agent` allow rules, and all `Monitor` allow rules (added
# upstream in v2.1.236, because Claude Code runs Monitor commands through the
# shell). https://code.claude.com/docs/en/changelog 2.1.327 widens the
# package-manager class to path and version forms (`/usr/bin/npm run:*`); the
# page does not say so yet. Narrow
# rules such as `Bash(npm test)` carry over and must never match.
#
# The bodies below cover the six SHELL shapes only. `Agent` and `Monitor` are
# whole-tool classes with no command shape to match, so each consuming driver
# tests them on the tool token; there is nothing here for them to share.
#
# python accepts version suffixes (python3, python3.11, python2.7): pinned
# minor-version binaries are the same interpreter-led grant shape.
CCPERM_INTERP_BODY='python[0-9.]*|node|deno|bun|ruby|perl|php|bash|sh|zsh|pwsh|osascript|Rscript'
CCPERM_RUNNER_BODY='npx|bunx|uvx|pnpm dlx|yarn dlx|pipx run|uv run|npm|pnpm|yarn'
CCPERM_SCRIPT_BODY='py|sh|rb|js|ts|mjs|cjs|pl|php'
# The wrappers Claude Code strips before matching a Bash rule, per
# https://code.claude.com/docs/en/permissions#process-wrappers (read
# 2026-11-21). They are Bash-only: that section strips them from Bash rules.
CCPERM_WRAPPER_BODY='timeout|time|nice|nohup|stdbuf|command|builtin|noglob'

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
#      build)) carries no * and is not matched. The `([\"' :])` before the `\*`
#      requires a separator, so `Bash(npmx *)` does not match the `npm` runner.
#      The runner takes the interpreter's path prefix (Bash(/usr/bin/npm
#      run:*)) and an `@<version>` suffix on its name (Bash(pnpm@9 dlx *)),
#      the path and version forms of the 2.1.327 note above.
#   4. a leading-glob command that resolves to a script (Bash(*.py:*))
#   5. a process wrapper followed only by a wildcard (Bash(timeout *)). A
#      wrapper with a fixed argument before the * (Bash(timeout 30 *)) is not
#      "followed only by a wildcard" and is not matched.
#   6. any shell rule whose command starts with a wildcard (Bash(* --version)).
#      It subsumes 1 and 4, which stay separate so a driver can name them.
#   7. the two wildcarded-path forms upstream names: a rule that starts with
#      `$HOME` (Bash($HOME/bin/*)), and a program written as a Windows
#      backslash path (PowerShell(C:\tools\x.exe *)) other than a `.\` path,
#      which https://code.claude.com/docs/en/changelog 2.1.327 restored. The
#      program must name something before its first backslash, so a
#      frontmatter rule read raw with a YAML-escaped quote
#      (Bash(\"${CLAUDE_SKILL_DIR}/x.sh\":*)) is not a path. The page says
#      "some" wildcarded paths and names no others, so other path forms
#      (Bash(/opt/tools/*), Bash(${HOME}/bin/*)) are left out.
#
# Each alternative captures the whole Tool(...) spec. The specifier may contain
# one nesting level of literal parentheses (CCPERM_BALANCED_ERE, the same limit
# as CCPERM_TOOL_TOKEN_ERE), so an inner `)` does not end the rule: a bare `[^)]*`
# would cut a documented path such as `Edit(./Finance (2024)/**)` short.
#
# The alternatives are also exposed individually so a driver that must NAME
# the class a rule fell into (the entry diff's drop reason) tests them one at a
# time instead of re-deriving the wrapping; the union stays the P1 detector's
# single match target and is composed from them, never written twice.
CCPERM_BALANCED_ERE='([^()]|\([^()]*\))*'
CCPERM_P1_BLANKET_ERE="(Bash|PowerShell)\\(\\*\\)"
CCPERM_P1_INTERP_ERE="(Bash|PowerShell)\\([\"' ]*([^()\"' ]*[/\\\\])?(${CCPERM_INTERP_BODY})([\"' :]${CCPERM_BALANCED_ERE})?\\*${CCPERM_BALANCED_ERE}\\)"
CCPERM_P1_RUNNER_ERE="(Bash|PowerShell)\\([\"' ]*([^()\"' ]*[/\\\\])?(${CCPERM_RUNNER_BODY})(@[^()\"' :]*)?([\"' :]${CCPERM_BALANCED_ERE})?([\"' :])\\*${CCPERM_BALANCED_ERE}\\)"
CCPERM_P1_SCRIPTGLOB_ERE="(Bash|PowerShell)\\([\"' ]*\\*${CCPERM_BALANCED_ERE}\\.(${CCPERM_SCRIPT_BODY})${CCPERM_BALANCED_ERE}\\)"
CCPERM_P1_WRAPPER_ERE="Bash\\([\"' ]*(${CCPERM_WRAPPER_BODY})[\"' :]+\\*[\"' ]*\\)"
CCPERM_P1_LEADING_ERE="(Bash|PowerShell)\\([\"' ]*\\*${CCPERM_BALANCED_ERE}\\)"
CCPERM_P1_PATH_ERE="(Bash|PowerShell)\\([\"' ]*(\\\$HOME([/\\\\\"' :]${CCPERM_BALANCED_ERE})?|([^()\"' .\\\\]|[^()\"' \\\\][^()\"' \\\\]+)\\\\${CCPERM_BALANCED_ERE})\\*${CCPERM_BALANCED_ERE}\\)"
CCPERM_P1_ERE="${CCPERM_P1_BLANKET_ERE}|${CCPERM_P1_INTERP_ERE}|${CCPERM_P1_RUNNER_ERE}|${CCPERM_P1_SCRIPTGLOB_ERE}|${CCPERM_P1_WRAPPER_ERE}|${CCPERM_P1_LEADING_ERE}|${CCPERM_P1_PATH_ERE}"

# Splits rule text into top-level `Tool` / `Tool(...)` tokens. The payload is
# one token, so a tool name inside another rule's payload (Bash(echo Agent),
# Bash(grep PowerShell *)) never surfaces as its own token. The payload accepts
# one level of nested parentheses (Bash(echo $(date) Agent), Edit(./Finance
# (2024)/**)) so an inner `)` does not end the token early. ERE cannot balance
# arbitrary depth, so a second nesting level still splits. Trailing text after
# the closing parenthesis (Bash(ls) x) is not part of the token: Claude Code
# reports that shape as a malformed Tool(content) rule. A driver that keeps only
# the token hides the malformation; compare the tokens with the original text.
#
# Drivers use this to tell a whole-tool grant (bare `Bash`, bare or scoped
# `Agent`) from a scoped rule that merely mentions a tool name in its payload.
CCPERM_TOOL_TOKEN_ERE="[A-Za-z_][A-Za-z0-9_]*(\\(${CCPERM_BALANCED_ERE}\\))?"
