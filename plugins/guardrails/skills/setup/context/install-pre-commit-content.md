# `apply install-pre-commit-content` (opt-in, explicit argument only)

The DEPTH layer for content invariants that Write|Edit-matched guards alone cannot
close: a git `pre-commit` hook scanning every staged blob for the same high-confidence
secret patterns and hardcoded machine-path patterns the CC-layer
`secret-pattern-detection` / `hardcoded-path-check` guards use, via copies of the same
libs (`lib/secret-detection/`, `lib/path-detection/`). Catches the damage class a Bash
staged write (`jq … > /tmp/x && mv /tmp/x dest`) can introduce while skipping those
tool-matched gates. Never runs from bare `apply`; only the explicit
`install-pre-commit-content` argument installs anything.

**Lane: personal `.git/hooks/` only.** Same personal-lane contract as
`install-commit-msg`: invisible to teammates, uncommitted, removable by deleting the
hook and its `guardrails-content-lib/` directory. A committed team lane is deliberately
NOT scaffolded; when the team wants shared enforcement, add the same checks to the
repo's hook manager or CI instead.

**Preflight: refuse rather than surprise (run all, report, stop on any REFUSE):**

1. **Managed-repo detection.** `git config --get core.hooksPath` non-empty, or
   `lefthook.yml`/`.lefthook.yml`, `.husky/`, or a `pre-commit` config managing hooks →
   REFUSE: the repo's hook manager owns this surface. Remediation: add the content scan
   to the manager's own `pre-commit` entry (point it at the shipped template + libs, or
   an equivalent CI job).
2. **Existing `pre-commit` hook.** Present and NOT sentinel-marked → offer exactly two
   paths and default to refusing: **chain** (rename the existing hook to
   `pre-commit.pre-guardrails`; the installed hook runs it first and its rejection is
   final) or **refuse** (leave everything untouched). Never overwrite.
3. **Sentinel-marked hook already installed** → idempotent re-install: overwrite the
   guardrails-owned hook and refresh `guardrails-content-lib/` in place, report
   "refreshed".

**Install (on a clean preflight):** copy
`${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/pre-commit-content-invariants.sh` to
`<git-dir>/hooks/pre-commit`, and copy `${CLAUDE_PLUGIN_ROOT}/lib/secret-detection/` plus
`${CLAUDE_PLUGIN_ROOT}/lib/path-detection/` to
`<git-dir>/hooks/guardrails-content-lib/{secret,path}-detection/` (resolve `<git-dir>` via
`git rev-parse --absolute-git-dir`), `chmod +x` the hook.

**Verify + report:** stage a throwaway clean file and a throwaway file containing a
synthetic high-confidence secret pattern (e.g. a `ghp_` + 36-char fixture, never a live
token); show both hook outcomes; state the removal path (delete `pre-commit` and
`guardrails-content-lib/`; restore `pre-commit.pre-guardrails` if chaining renamed one).

**Known interactions (state them in the report):**

- `--no-verify` skips pre-commit hooks; `block-no-verify` refuses that flag in Claude
  sessions. The designed exit is fixing the staged content.
- The CC-layer Write|Edit guards usually block first in a Claude session; this hook is
  the backstop for write paths those guards never see (Bash staged moves, editor
  saves, IDE commits, humans outside Claude).
- `block-hook-bypass`'s same-command staged-move detector narrows one spelling; this
  hook closes the damage class regardless of write path.
