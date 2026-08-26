# `apply install-commit-msg` (opt-in, explicit argument only)

The DEPTH layer of commit-convention enforcement: a git `commit-msg` hook validating every
commit on this machine in this repo: editor commits, `git commit -F <file>`, IDE
integrations, humans outside Claude, against the same team-tracked pattern the CC-layer
`block-convention-violation` guard reads, through a copy of the same resolver. Never runs
from bare `apply`; only the explicit `install-commit-msg` argument installs anything.

**Lane: personal `.git/hooks/` only.** This writes the CURRENT OPERATOR's repo-local hooks
directory, invisible to teammates, uncommitted, removable by deleting two files. A
committed team lane (`core.hooksPath` pointing at a tracked directory) is deliberately NOT
scaffolded: `core.hooksPath` changes are exactly what the `block-no-verify` guard refuses
as a hook-bypass shape, and pointing every teammate's git at a tracked hooks dir is a team
decision made by a human in a PR, not by this skill. When the team wants shared
enforcement, say so and point at a commit-msg entry in the repo's own hook manager
(lefthook/husky/CI) instead.

**Preflight: refuse rather than surprise (run all, report, stop on any REFUSE):**

1. **Managed-repo detection.** `git config --get core.hooksPath` non-empty, or
   `lefthook.yml`/`.lefthook.yml`, `.husky/`, or a `pre-commit` config managing hooks →
   REFUSE: the repo's hook manager owns this surface; installing behind its back invites
   silent shadowing. Remediation: add the convention check to the manager's own
   `commit-msg` entry.
2. **Existing `commit-msg` hook.** Present and NOT sentinel-marked → offer exactly two
   paths and default to refusing: **chain** (rename the existing hook to
   `commit-msg.pre-guardrails`; the installed hook runs it first and its rejection is
   final) or **refuse** (leave everything untouched). Never overwrite. This includes an
   operator's machine-local commit-msg gate. Chaining preserves it.
3. **Sentinel-marked hook already installed** → idempotent re-install: overwrite the two
   guardrails-owned files in place (template may have updated), report "refreshed".

**Install (on a clean preflight):** copy `${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/commit-msg-convention.sh`
to `<git-dir>/hooks/commit-msg` and `${CLAUDE_PLUGIN_ROOT}/hooks/resolve-convention-pattern.sh`
to `<git-dir>/hooks/guardrails-resolve-convention.sh` (resolve `<git-dir>` via
`git rev-parse --absolute-git-dir`; in a worktree `.git` is a file), `chmod +x` both.

**Verify + report:** run the installed hook against a throwaway conforming and violating
message file and show both outcomes; state the removal path (delete the two files; restore
`commit-msg.pre-guardrails` to `commit-msg` if chaining renamed one) and that
**unresolved = no enforcement**. With no team-tracked `subject_pattern` the hook
passes everything, so installing before `/source-control:setup apply` writes a convention
is inert, not harmful.

**Known interactions (state them in the report):**

- `--no-verify` skips commit-msg hooks, and the guardrails `block-no-verify` guard blocks
  that flag in Claude sessions. By design the only exit from a rejection is a compliant
  subject (the hook's message says exactly that and never suggests bypass).
- The CC-layer `block-convention-violation` guard usually blocks a violating subject
  before git ever runs, so this hook firing in a Claude session means the CC layer was
  bypassed or disabled. It is the backstop, not the primary UX.
- Convention-inference tooling must skip sentinel-marked hooks (the
  `guardrails-commit-msg-convention` marker). The hook is derived FROM the tracked
  config and is not an independent convention signal.
