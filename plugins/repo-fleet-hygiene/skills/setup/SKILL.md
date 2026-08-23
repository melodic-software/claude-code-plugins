---
description: "Verify and configure repo-fleet-hygiene for a consumer project. check inspects the optional .claude/repo-fleet-hygiene.conf read-only (presence, parse validity, path resolution); apply creates or updates it — adding bounded fleet roots, exact repositories, and remote-keyed canonical checkout overrides — preserving unrelated entries. Use when: 'set up repo fleet audit', 'is repo-fleet-hygiene configured', 'configure fleet roots', 'canonical repo override', 'dotfiles-manager checkout'. Re-runnable and safe."
user-invocable: true
disable-model-invocation: true
argument-hint: "check | apply [--config <path>] [--root <dir>]... [--repo <dir>]... [--canonical <github.com/owner/repo=path>]... [--ack-unavailable <github.com/owner/repo>]... [--skip <name>]... [--max-depth <1..12>]"
---

## Purpose

Verify and manage the audit's optional Git-format configuration. Setup owns only this file; it never
edits Claude Code settings, `pluginConfigs`, Git remotes, branches, worktrees, or the installed plugin.

The config file itself is optional to *create*, but a no-argument `/repo-fleet-hygiene:audit` now
requires scope from somewhere: CLI bare path / `--root` / `--repo`, or `fleet.root` / `fleet.repo`
entries in a consumed config. Absence of every config on the ladder is therefore INFO for `check`
(nothing to validate yet) and a hard failure for a subsequent no-argument audit — not a silent
default to the current project. Check-centric per the uniform setup contract
(`docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable" in the marketplace repository):
`check` inspects read-only; `apply` creates or updates the file, then re-runs `check`. No argument
or `check` runs the check; `apply` runs the check first, then the write. All non-interactive: when
the arguments fully specify the change, `apply` proceeds without prompting.

Default config path: `${CLAUDE_PROJECT_DIR}/.claude/repo-fleet-hygiene.conf`. An explicit `--config`
may choose another path. Resolve relative roots/repos/canonical paths from the config file directory.

**Scoping rule (state it in `check`/`apply` output):** the audit consumes config through a ladder —
explicit `--config`, else the project-scoped default above, else the user-global
`~/.claude/repo-fleet-hygiene.conf`. A project-scoped config is therefore consumed only when the
audit runs with that same project directory; a fleet config meant to apply from every project
belongs at the user-global path (`apply --config ~/.claude/repo-fleet-hygiene.conf`). The audit
report header names which config (if any) was consumed.

## Argument grammar

```text
check | apply [--config <path>] [--root <dir>]... [--repo <dir>]...
        [--canonical <github.com/owner/repo=path>]... [--ack-unavailable <github.com/owner/repo>]...
        [--skip <name>]... [--max-depth <1..12>]
```

`--max-depth` writes `[fleet] maxDepth`; `--skip` writes repeatable `[fleet] skip` entries. This
skill owns the config file that carries both. Explicit `fleet.skip` entries **replace** the audit's
default discovery skip list (they do not append) — say that when writing them, because "extend" is
the naive reading. To extend without shrinking, write the three replaceable defaults
(`node_modules`, `vendor`, `.venv`) plus the extra names. `.`, `..`, and `.git` stay skipped
unconditionally and do not need to be written.

## `check` (read-only)

The config file and the grammar below are the source of truth. Probe, report a PASS/FAIL/INFO table
with one remediation line per FAIL, and modify nothing. Do NOT run the collector — that is
`/repo-fleet-hygiene:audit`; `check` only validates the configuration the audit would consume, using
`git config --file` and read-only filesystem probes.

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
7. **Discovery skip names** — INFO listing each `fleet.skip` entry. FAIL any value that is empty or
   contains a path separator (must be a bare directory name). Remind that any present `fleet.skip`
   **replaces** the audit default skip list rather than appending.

## `apply` (idempotent)

Run `check`, then create or update the config from the supplied arguments.

1. Parse only the declared argument grammar. Validate every root/repository/canonical path with
   read-only filesystem and `git rev-parse` checks. Normalize canonical keys to
   `github.com/owner/repository` (lowercase host, case-preserving owner/name is acceptable).
   Validate `--max-depth` as an integer in `1..12` and write it as `[fleet] maxDepth`; this skill
   owns the file that carries it, so it must be settable here rather than by hand-editing.
   Validate each `--ack-unavailable` value as a normalizable `github.com/owner/repository`
   (no filesystem probe — the identity is expected to be inaccessible); write it as a repeatable
   `[fleet] ackUnavailable` entry, deduplicating case-insensitively against entries already
   present. Like roots/repos, apply is additive — removing an acknowledgment is a manual edit of
   the consumer's own config file.
   Validate each `--skip` value as a bare directory name (reject empty and any path separator);
   write it as a repeatable `[fleet] skip` entry, deduplicating exact matches against entries
   already present. State the replace semantics when writing: any `fleet.skip` present replaces the
   audit's default skip list (`node_modules`, `vendor`, `.venv`) rather than appending — to
   extend, include those three defaults plus the new names. `.`, `..`, and `.git` stay skipped
   unconditionally. Removing a skip entry is a manual edit.
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
   and the user must see a deterministic diff. Preserve comments and unrelated sections. Prefer a
   path relative to the config file's directory for any root/repository/canonical target expressible
   that way — the grammar resolves relative paths from that directory and both forms audit
   identically, while some consumer environments run a write-time path-portability guard that rejects
   absolute paths in tracked config. "Expressible that way" is the real constraint: on Windows, no
   relative path exists between two volumes, so a fleet root on `D:` with a config on `C:` has only
   the absolute form. Write the absolute path, and say in the report that the relative form was
   unavailable because the target is on another volume — otherwise the guard's rejection reads as a
   consumer mistake. This preference is prose guidance followed by the model, not a property a
   deterministic component enforces; treat it as a default to justify departing from, not a
   guarantee.
5. Verify after remediation — re-run every `check` probe against the written file (never claim success on
   the edit alone). Config-only, exactly as `check` defines them:

   - **Parse validity** — `git config --file "<config-path>" --list >/dev/null`
   - **Entry resolution** — for each `[fleet] root`/`repo` and each `[canonical …] path`, resolve from
     the config directory and confirm the directory exists and (for roots/repos) `git rev-parse` succeeds
     read-only
   - **`maxDepth`** — when present, confirm it is an integer in `1..12`
   - **Canonical identity** and **acknowledged identities** — confirm each key/value normalizes to
     `github.com/owner/repository`
   - **Discovery skip names** — when present, confirm each `fleet.skip` value is a bare directory
     name (non-empty, no path separator)

   Do **not** invoke the collector to verify a write. It is the full fleet walk this skill says it
   never runs — per-repository network queries across every configured root, minutes on a real fleet
   — and it proves nothing about the file that the `check` probes do not already prove. If the user
   explicitly wants an end-to-end run, say that it is a real audit and hand off by invoking
   `/repo-fleet-hygiene:audit` via the Skill tool.

6. Report path, inferred/explicit entries, preserved entries, and the config-verification result.

Re-running `apply` with the same arguments after everything resolves changes nothing and reports
"already configured".

## Configuration grammar

```gitconfig
[fleet]
    root = ../../repos/github.com   # repeatable discovery root
    repo = ../../special/repo      # repeatable exact target
    maxDepth = 5                   # integer 1..12
    ackUnavailable = github.com/owner/repository   # repeatable; acknowledge a known-inaccessible identity
    skip = vendor                  # repeatable; REPLACE default discovery skip list (not append)

[canonical "github.com/owner/repository"]
    path = ../../../canonical-checkout
```

`ackUnavailable` demotes a 404/403 `github-identity-unavailable` finding for that identity from
`UNKNOWN` to `ACKNOWLEDGED` in the audit report — still reported, never suppressed, and never
affecting non-404/403 failures or successful-response evidence. Use it for foreseeable 404s:
upstream repositories made private or deleted, or repositories owned by a different GitHub account
than the authenticated `gh` login.

`skip` replaces the audit's default discovery skip list (`node_modules`, `vendor`, `.venv`)
whenever any entry is present. It does **not** append — a lone `skip = third_party` means only
`third_party` is skipped (plus unconditional `.` / `..` / `.git`). To extend the defaults, write
those three plus the extra names. CLI `--skip` and config `fleet.skip` compose additively with each
other the same way other scope inputs do.

Resolution priority is explicit audit CLI override, canonical config entry, then the discovered
checkout's own **main worktree** (the first record of `git worktree list --porcelain`). A canonical
override is therefore not needed merely to steer the audit away from a linked worktree — the audit
resolves that itself. Never add one because two directory names look similar; verify the normalized
GitHub remote identity on both sides first.

## What this skill does NOT do

- Run a fleet audit — that is `/repo-fleet-hygiene:audit`. `check` validates config only; it never
  walks the fleet.
- Write Claude Code settings, `pluginConfigs`, the plugin cache, or any machine-local state — the
  config is the consumer's own tracked file.
- Touch Git remotes, branches, or worktrees.

## Gotchas

- **Absolute paths in tracked config can be rejected by consumer write guards.** A root, repository, or
  canonical target written as an absolute path may trip a consumer's write-time path-portability guard;
  the same target written relative to the config file's directory passes and resolves identically, so
  `apply` prefers the relative form — except across Windows volumes, where no relative form exists and
  the absolute path is the only honest option. When that happens, write the absolute path, say in the
  report that no relative path exists between volumes, and name the consumer's remedies if the guard
  still rejects the write: colocate the config with the fleet root on one volume, exempt this file or
  path from the guard, or keep a user-global config outside the guard's scan — do not fabricate a
  relative path or leave the consumer to conclude they misconfigured something.
- **A project-scoped config is consumed only from its own project.** Per the Scoping rule above, a
  config meant to apply from every project belongs at the user-global
  `~/.claude/repo-fleet-hygiene.conf`, not a per-project path — otherwise the audit silently narrows to
  the project it was authored in. Two cases collapse this warning, and `check` should say which one
  applies rather than repeating a caution that cannot bite: when the project directory *is* the home
  directory both rungs name the same file, and when no project directory reaches the audit (the
  session did not supply one) the project rung is not merely aliased but unreachable, leaving the
  user-global path the only one that can be consumed.
- **Config-supplied scope is additive to the audit's CLI scope.** A configured root is walked even
  when the audit is invoked with an explicit `--repo`, so a persisted fleet config widens every later
  run. The audit's `Scope:` header line names each contributing rung; there is currently no way to
  suppress a config for a single run.
