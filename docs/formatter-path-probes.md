# Formatter / lint hook PATH probes

Inventory of PostToolUse hooks that resolve a formatter or linter binary, and how they
degrade when the probe misses. Cloud / managed sessions are the failure class: hook
processes inherit **Claude Code's own environment** (hooks reference), not the interactive
shell's profile, so an nvm-provisioned global install the Bash tool can see is invisible to
every `command -v` probe here (#2732; precedent #811).

**Dispatch completeness is a prerequisite of this checklist.** If no `PostToolUse` hook
completes, these probes never run and files land unformatted with no skip notice. That is a
host or harness dispatch failure, not a PATH miss, and
[#3549](https://github.com/melodic-software/claude-code-plugins/issues/3549) carries it.

**Claim:** "no `PostToolUse` hook completes" is not a general property of Claude Code 2.1.x:
Linux 2.1.258 completes the two-line probe and a real `typos-format` `PostToolUse` with a full
plugin fleet. **Basis:** the 2026-09-06 triage probe on #3549 (both `pre-` and `post-` lines
present, isolated `CLAUDE_CONFIG_DIR` and real `~/.claude`). **As of:** 2026-09-28.
**Recheck:** the Windows `claude --debug` result on #3549. Until it names a cause, do not raise
in-repo `PostToolUse` timeouts; the change cannot be tested without it.

This document is the fleet checklist. Per-hook notices must:

1. Say the skip is for **this edit** (the probe re-runs; only the notice latches).
2. Name the environment-inheritance cause (not "install it again").
3. Prefer a **repo-local / filesystem** install route when one exists.
4. Append `PATH probed: …` so the miss is diagnosable. Prefer plausible
   directories (user/repo install locations); collapse Claude Code plugin-bin
   entries to a count so the dump stays short enough for a later re-notice.
5. **Never** widen the probe into nvm/rbenv layout guesses. That is bootstrap work
   (#2739 / #2748), not a hook-side search expansion.

The formatter and lint plugins below no longer carry per-edit `PostToolUse` rows. A formatter's
`PostToolBatch` row rewrites silently and skips silently when its tool is missing; the git
pre-commit entry is where a missing tool surfaces, under the check-placement contract: an agent
commit fails with the install command and a `checks.skipmissing` key, a person gets a notice.
The per-edit notice rules above apply to the hooks this table no longer lists.

| Plugin | Batch row / pre-commit entry | Probe order | Filesystem / repo-local route | Missing-tool report | Check skill |
|---|---|---|---|---|---|
| `markdown-format` | `hooks/markdown-format.sh` / `git-hooks/markdown-check.sh` | `command -v markdownlint-cli2`, then walk `node_modules/.bin` from the file up to the repo root | `npm i -D markdownlint-cli2` | pre-commit contract | `/markdown-format:check`; SessionStart probe |
| `biome-format` | `hooks/biome-format.sh` / `git-hooks/biome-check.sh` | `node_modules/.bin/biome` under the governing config, then `command -v biome` | `npm i -D @biomejs/biome` | pre-commit contract | `/biome-format:check`; SessionStart probe |
| `ruff-format` | `hooks/ruff-format.sh` / `git-hooks/ruff-check.sh` | `.venv/{bin,Scripts}/ruff`, then `command -v ruff` | project `.venv` / `pip install ruff` | pre-commit contract | `/ruff-format:check`; SessionStart probe |
| `bash-format` | `hooks/bash-format.sh` / `git-hooks/shell-check.sh` | `command -v shfmt`, `command -v shellcheck` | host package / release binary (no npm form) | pre-commit contract | `/bash-format:check`; SessionStart probe |
| `typos-format` | none / `git-hooks/typos-check.sh` | `command -v typos` | cargo / release binary | pre-commit contract | `/typos-format:check`; SessionStart probe |
| `go-format` | `hooks/go-format.sh` / `git-hooks/goimports-format.sh` | `command -v goimports`, `command -v go` | `go install …/goimports@latest` | pre-commit contract | `/go-format:check`; SessionStart probe |
| `powershell-format` | none / `git-hooks/powershell-check.sh` | `command -v pwsh`, then the PSScriptAnalyzer module | host PowerShell install | pre-commit contract (pwsh and PSScriptAnalyzer) | `/powershell-format:check`; SessionStart probe |
| `actionlint` | none / `git-hooks/actionlint-check.sh` | `command -v actionlint` | release binary / `go install` | pre-commit contract | `/actionlint:check`; SessionStart probe |
| `eol-normalizer` | `hooks/normalize-eol.sh` | `command -v perl` (optional fast path) | pure-shell fallback when perl missing | n/a (degrades, does not skip) | n/a |

Bootstrap hardening that puts fleet tools on the **harness** process PATH (or pins them as
repo `devDependencies`) is out of scope for the per-hook notice sweep. See #2739.
