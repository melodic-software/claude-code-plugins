---
name: setup
description: "Verify and configure repo-fleet-hygiene for a consumer project. check inspects the optional .claude/repo-fleet-hygiene.conf read-only (presence, parse validity, path resolution); apply creates or updates it — adding bounded fleet roots, exact repositories, and remote-keyed canonical checkout overrides — preserving unrelated entries. Use when: 'set up repo fleet audit', 'is repo-fleet-hygiene configured', 'configure fleet roots', 'canonical repo override', 'dotfiles-manager checkout'. Re-runnable and safe."
user-invocable: true
disable-model-invocation: true
argument-hint: "check | apply [--config <path>] [--root <dir>]... [--repo <dir>]... [--canonical <github.com/owner/repo=path>]..."
---

## Purpose

Verify and manage the audit's optional Git-format configuration. Setup owns only this file; it never
edits Claude Code settings, `pluginConfigs`, Git remotes, branches, worktrees, or the installed plugin.

The config is optional — with none, the audit runs against the current project by default — so its
absence is a reported INFO, never a FAIL. `check` inspects read-only; `apply` creates or updates the
file, then re-runs `check`. No argument or `check` runs the check; `apply` runs the check first, then
the write. All non-interactive: when the arguments fully specify the change, `apply` proceeds without
prompting.

Default config path: `${CLAUDE_PROJECT_DIR}/.claude/repo-fleet-hygiene.conf`. An explicit `--config`
may choose another path. Resolve relative roots/repos/canonical paths from the config file directory.

**Scoping rule (state it in `check`/`apply` output):** the audit consumes config through a ladder —
explicit `--config`, else the project-scoped default above, else the user-global
`~/.claude/repo-fleet-hygiene.conf`. A project-scoped config is therefore consumed only when the
audit runs with that same project directory; a fleet config meant to apply from every project
belongs at the user-global path (`apply --config ~/.claude/repo-fleet-hygiene.conf`). The audit
report header names which config (if any) was consumed.

## `check` (read-only)

The audit script (`${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/audit-fleet.sh`) and the config file are
the source of truth. Probe, report a PASS/FAIL/INFO table with one remediation line per FAIL, and
modify nothing. Do NOT run the fleet walk itself — that is `/repo-fleet-hygiene:audit`; `check` only
validates the configuration the audit would consume.

1. **Config presence** — resolve the config path (`--config` or the default). Absent → INFO naming
   the full ladder: the audit next probes the user-global `~/.claude/repo-fleet-hygiene.conf` (report
   whether one exists there) and otherwise defaults to the current project; `apply` scaffolds a
   config only if the user wants bounded roots or overrides.
2. **Parse validity** — present config: `git config --file "<path>" --list >/dev/null`. A non-zero exit
   is FAIL with the parse error in the remediation line. Never `source` the file.
3. **Entry resolution** — for each `[fleet] root`/`repo` and each `[canonical …] path`, resolve it from
   the config directory and confirm the directory exists and (for roots/repos) `git rev-parse` succeeds
   read-only. A referenced path that does not resolve is FAIL, naming the entry.
4. **`maxDepth`** — present and outside `1..12` is FAIL; absent is INFO (the audit's own default applies).
5. **Canonical identity** — INFO for each `[canonical "github.com/owner/repository"]` entry: report the
   normalized key. Flag as FAIL only a key that is not a normalizable `github.com/owner/repository`.
6. **Acknowledged identities** — INFO listing each `fleet.ackUnavailable` entry (normalized). FAIL any
   value that is not a normalizable `github.com/owner/repository`.

## `apply` (idempotent)

Run `check`, then create or update the config from the supplied arguments.

1. Parse only the declared argument grammar. Validate every root/repository/canonical path with
   read-only filesystem and `git rev-parse` checks. Normalize canonical keys to
   `github.com/owner/repository` (lowercase host, case-preserving owner/name is acceptable).
2. If the config exists, read it with `git config --file <path> --list --show-origin`. Preserve every
   unrelated entry. Never source it.
3. State the proposed additions/updates before writing. With complete arguments, proceed
   non-interactively; otherwise ask only for the missing values. An empty invocation may create the
   minimal current-project config:

   ```gitconfig
   [fleet]
       repo = ..
       maxDepth = 5
   ```

   (`..` is relative to `.claude/` and therefore names `${CLAUDE_PROJECT_DIR}`.)
4. Write/update with an ordinary file edit, not `git config --file ... --add`: the file may be tracked
   and the user must see a deterministic diff. Preserve comments and unrelated sections.
5. Verify after remediation — re-run the `check` probes against the written file (never claim success on
   the edit alone):

   ```bash
   git config --file "<config-path>" --list >/dev/null
   bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/audit-fleet.sh" --config "<config-path>"
   ```

6. Report path, inferred/explicit entries, preserved entries, and the read-only audit result.

Re-running `apply` with the same arguments after everything resolves changes nothing and reports
"already configured".

## Configuration grammar

```gitconfig
[fleet]
    root = ../../repos/github.com   # repeatable discovery root
    repo = ../../special/repo      # repeatable exact target
    maxDepth = 5                   # integer 1..12
    ackUnavailable = github.com/owner/repository   # repeatable; acknowledge a known-inaccessible identity

[canonical "github.com/owner/repository"]
    path = ../../../canonical-checkout
```

`ackUnavailable` demotes a 404/403 `github-identity-unavailable` finding for that identity from
`UNKNOWN` to `ACKNOWLEDGED` in the audit report — still reported, never suppressed, and never
affecting non-404/403 failures or successful-response evidence. Use it for foreseeable 404s:
upstream repositories made private or deleted, or repositories owned by a different GitHub account
than the authenticated `gh` login.

Resolution priority is explicit audit CLI override, canonical config entry, then discovered checkout's
`git rev-parse --show-toplevel`. Never add a canonical override merely because two directory names look
similar; verify the normalized GitHub remote identity on both sides first.

## What this skill does NOT do

- Run a fleet audit — that is `/repo-fleet-hygiene:audit`. `check` validates config only; it never
  walks the fleet.
- Write Claude Code settings, `pluginConfigs`, the plugin cache, or any machine-local state — the
  config is the consumer's own tracked file.
- Touch Git remotes, branches, or worktrees.
