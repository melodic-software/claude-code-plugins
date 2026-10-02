---
description: "Verify and configure repo-fleet-hygiene for a consumer project. check inspects the optional .claude/repo-fleet-hygiene.conf read-only (presence, parse validity, path resolution); apply creates or updates it by adding bounded fleet roots, exact repositories, and remote-keyed canonical checkout overrides, preserving unrelated entries. Use when: 'set up repo fleet audit', 'is repo-fleet-hygiene configured', 'configure fleet roots', 'canonical repo override', 'dotfiles-manager checkout'. Re-runnable and safe."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/setup-config.sh:*)
argument-hint: "[check|apply] [--config <path>] [--root <dir>]... [--repo <dir>]... [--skip <name>]..."
---

**Arguments.** `[check|apply] [--config <path>] [--root <dir>]... [--repo <dir>]... [--skip <name>]...`. Full form: [check|apply] [--config <path>] [--root <dir>]... [--repo <dir>]... [--canonical <github.com/owner/repo=path>]... [--ack-unavailable <github.com/owner/repo>]... [--skip <name>]... [--extend-skip <name>]... [--max-depth <1..12>]

## Purpose

Verify and manage the audit's optional Git-format configuration. Setup owns only this file; it never
edits Claude Code settings, `pluginConfigs`, Git remotes, branches, worktrees, or the installed plugin.

The config file itself is optional to *create*, but a no-argument `/repo-fleet-hygiene:audit`
requires scope from somewhere: CLI bare path / `--root` / `--repo`, or `fleet.root` / `fleet.repo`
entries in a consumed config. Absence of every config on the ladder is therefore INFO for `check`
(nothing to validate yet) and a hard failure for a subsequent no-argument audit, not a silent
default to the current project. Check-centric per the uniform setup contract
(`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the marketplace repository):
`check` inspects read-only; `apply` creates or updates the file, then re-runs `check`. No argument
or `check` runs the check; `apply` runs the check first, then the write. All non-interactive: when
the arguments fully specify the change, `apply` proceeds without prompting.

Default config path: `${CLAUDE_PROJECT_DIR}/.claude/repo-fleet-hygiene.conf`. An explicit `--config`
may choose another path. Resolve relative roots/repos/canonical paths from the config file directory.

**Scoping rule (state it in `check`/`apply` output):** the audit consumes config through a ladder:
explicit `--config`, else the project-scoped default above, else the user-global
`~/.claude/repo-fleet-hygiene.conf`. A project-scoped config is therefore consumed only when the
audit runs with that same project directory; a fleet config meant to apply from every project
belongs at the user-global path (`apply --config ~/.claude/repo-fleet-hygiene.conf`). The audit
report header names which config (if any) was consumed.

## Argument grammar

```text
check | apply [--config <path>] [--root <dir>]... [--repo <dir>]...
        [--canonical <github.com/owner/repo=path>]... [--ack-unavailable <github.com/owner/repo>]...
        [--skip <name>]... [--extend-skip <name>]... [--max-depth <1..12>]
```

`--max-depth` writes `[fleet] maxDepth`; `--skip` writes repeatable `[fleet] skip` entries;
`--extend-skip` writes repeatable `[fleet] skipAppend` entries. This skill owns the config file
that carries them. See "Configuration grammar" below for the `skip` replace semantics, and state
them whenever you write a `skip` entry, because "extend" is the naive reading. An operator who
wants to add names to the defaults wants `--extend-skip`.

## `check` (read-only)

The config file and the grammar below are the source of truth. Probe, report a PASS/FAIL/INFO table
with one remediation line per FAIL, and modify nothing. Do NOT run the collector. That is
`/repo-fleet-hygiene:audit`; `check` only validates the configuration the audit would consume, using
`git config --file` and read-only filesystem probes.

1. **Config presence**. Resolve the config path (`--config` or the default). Absent → INFO naming
   the full ladder: the audit next probes the user-global `~/.claude/repo-fleet-hygiene.conf` (report
   whether one exists there); with no config on the ladder and no scope argument, a bare
   `/repo-fleet-hygiene:audit` follows the no-scope ladder in that skill. `apply` scaffolds a
   config only if the user wants bounded roots or overrides.
2. **Parse validity**. Present config: `git config --file "<path>" --list >/dev/null`. A non-zero exit
   is FAIL with the parse error in the remediation line. Never `source` the file.
3. **Entry resolution**. For each `[fleet] root`/`repo` and each `[canonical …] path`, resolve it from
   the config directory and confirm the directory exists and (for roots/repos) `git rev-parse` succeeds
   read-only. A referenced path that does not resolve is FAIL, naming the entry.
4. **`maxDepth`**. Present and outside `1..12` is FAIL; absent is INFO (the audit's own default applies).
5. **Canonical identity**. INFO for each `[canonical "github.com/owner/repository"]` entry: report the
   normalized key. Flag as FAIL only a key that is not a normalizable `github.com/owner/repository`.
6. **Acknowledged identities**. INFO listing each `fleet.ackUnavailable` entry (normalized). FAIL any
   value that is not a normalizable `github.com/owner/repository`.
7. **Discovery skip names**. INFO listing each `fleet.skip` and `fleet.skipAppend` entry. FAIL any
   value that is empty or contains a path separator (must be a bare directory name). Remind that
   any present `fleet.skip` **replaces** the audit default skip list rather than appending, while
   `fleet.skipAppend` adds to whichever list is in effect.
8. **Tracked-file pair** (only when the config lives inside a git worktree, e.g. a project's
   tracked `.claude/repo-fleet-hygiene.conf`): resolve the worktree that owns the file
   (`git -C "$(dirname -- "<path>")" rev-parse --show-toplevel`) and run both probes there
   with a path relative to that toplevel: `git -C "<toplevel>" check-ignore -v -- "<rel>"`
   reports no match (a match is FAIL with the pattern, since teammates would never receive the
   config) AND `git -C "<toplevel>" ls-files --error-unmatch -- "<rel>"` exits 0 (non-zero is
   un-ignored but untracked; FAIL with "commit it to share with the team"). An explicit
   `--config` in another checkout is still that other worktree's file; do not run the pair
   against the current project's index. Skip both, saying so, when no owning worktree exists
   (user-global `~/.claude/…` or any path outside a repository). A git verdict there is
   meaningless.

## `apply` (idempotent)

Run `check`, then create or update the config from the supplied arguments.

1. Parse only the declared argument grammar. Validate every root/repository/canonical path with
   read-only filesystem and `git rev-parse` checks. Normalize canonical keys to
   `github.com/owner/repository` (lowercase host, case-preserving owner/name is acceptable).
   Validate `--max-depth` as an integer in `1..12` and write it as `[fleet] maxDepth`; this skill
   owns the file that carries it, so it must be settable here rather than by hand-editing.
   Validate each `--ack-unavailable` value as a normalizable `github.com/owner/repository`
   (no filesystem probe, the identity is expected to be inaccessible); write it as a repeatable
   `[fleet] ackUnavailable` entry, deduplicating case-insensitively against entries already
   present. Like roots/repos, apply is additive. Removing an acknowledgment is a manual edit of
   the consumer's own config file.
   Validate each `--skip` value as a bare directory name (reject empty and any path separator);
   write it as a repeatable `[fleet] skip` entry, deduplicating exact matches against entries
   already present. State the replace semantics from "Configuration grammar" when writing.
   Validate each `--extend-skip` value the same way and write it as a repeatable
   `[fleet] skipAppend` entry, deduplicating exact matches. Removing a skip entry is a manual edit.
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
4. Write `--root`, `--repo`, `--skip`, `--extend-skip`, and `--max-depth` by calling the bundled
   script, never by hand-editing the file:

   ```text
   ${CLAUDE_SKILL_DIR}/scripts/setup-config.sh apply [--config <path>] [--project-dir <dir>]
       [--root <dir>]... [--repo <dir>]... [--skip <name>]... [--extend-skip <name>]... [--max-depth <n>]
   ```

   It validates the same rules as step 1, writes each entry with `git config --file <path> --add`
   after an exact-match check (a repeated run reports "already configured" and changes nothing),
   preserves comments and unrelated entries, creates the parent directory, and refuses a symlink
   target. It exits 2 on a validation error and writes nothing. Without `--config` it writes
   `<project-dir>/.claude/repo-fleet-hygiene.conf` (`${CLAUDE_PROJECT_DIR}` when `--project-dir` is
   absent). The script takes only those five options. For `--canonical` and `--ack-unavailable`,
   which need the identity checks above, make an ordinary file edit so the user sees a deterministic
   diff, preserving comments and unrelated sections.

   The script writes each root and repository relative to the config file's directory, which the
   grammar resolves identically and which passes the write-time path-portability guard some consumer
   environments run on tracked config. Where no relative path exists (on Windows, two volumes: a
   fleet root on `D:` with a config on `C:`) it writes the absolute path; say in the report that the
   relative form was unavailable because the target is on another volume, so the guard's rejection
   is not mistaken for a consumer error. Write any hand-edited `--canonical` path the same way.
5. Verify after remediation. Re-run every `check` probe against the written file (never claim success on
   the edit alone). Config-only, exactly as `check` defines them:

   - **Parse validity**. `git config --file "<config-path>" --list >/dev/null`
   - **Entry resolution**. For each `[fleet] root`/`repo` and each `[canonical …] path`, resolve from
     the config directory and confirm the directory exists and (for roots/repos) `git rev-parse` succeeds
     read-only
   - **`maxDepth`**. When present, confirm it is an integer in `1..12`
   - **Canonical identity** and **acknowledged identities**. Confirm each key/value normalizes to
     `github.com/owner/repository`
   - **Discovery skip names**. When present, confirm each `fleet.skip` and `fleet.skipAppend`
     value is a bare directory name (non-empty, no path separator)
   - **Tracked-file pair** (when the config lives inside a git worktree, e.g. the tracked
     `.claude/repo-fleet-hygiene.conf`): resolve the owning worktree
     (`git -C "$(dirname -- "<config-path>")" rev-parse --show-toplevel`) and run both probes
     there with a toplevel-relative path: `git -C "<toplevel>" check-ignore -v -- "<rel>"`
     reports no match (a match is FAIL with the pattern, since teammates would never receive the
     config) AND `git -C "<toplevel>" ls-files --error-unmatch -- "<rel>"` exits 0 (non-zero
     means un-ignored but still untracked, the guaranteed state right after a fresh write;
     report "written but untracked: commit it to share with the team", never success). An
     explicit `--config` in another checkout is still that other worktree's file. Skip both,
     saying so, when no owning worktree exists. A git verdict there is meaningless.

   Do **not** invoke the collector to verify a write. It is the full fleet walk this skill says it
   never runs: per-repository network queries across every configured root, minutes on a real fleet,
   and it proves nothing about the file that the `check` probes do not already prove. If the user
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
    skipAppend = third_party       # repeatable; ADD to whichever skip list is in effect

[canonical "github.com/owner/repository"]
    path = ../../../canonical-checkout
```

`ackUnavailable` demotes a 404/403 `github-identity-unavailable` finding for that identity from
`UNKNOWN` to `ACKNOWLEDGED` in the audit report, still reported, never suppressed, and never
affecting non-404/403 failures or successful-response evidence. Use it for foreseeable 404s:
upstream repositories made private or deleted, or repositories owned by a different GitHub account
than the authenticated `gh` login.

`skip` replaces the audit's default discovery skip list (`vendor` plus the package-manager cache
trees `node_modules`, `.venv`, `.pnpm-store`, `.yarn`, `.npm`, `.cargo`, `.rustup`, `.gradle`, `.m2`,
`.nuget`, `__pycache__`, `.tox`) whenever any entry is present. It does **not** append. A lone
`skip = third_party` means only `third_party` is skipped (plus unconditional `.` / `..` / `.git`).
To extend the defaults, write `skipAppend = third_party` instead: `skipAppend` (and the audit's
`--extend-skip`) adds to whichever list is in effect, the defaults or an explicit `skip` list. CLI
`--skip` and config `fleet.skip` compose additively with each other the same way other scope inputs
do; so do `--extend-skip` and `fleet.skipAppend`.

Resolution priority is explicit audit CLI override, canonical config entry, then the discovered
checkout's own **main worktree** (the first record of `git worktree list --porcelain`). A canonical
override is therefore not needed merely to steer the audit away from a linked worktree. The audit
resolves that itself. Never add one because two directory names look similar; verify the normalized
GitHub remote identity on both sides first.

## What this skill does NOT do

- Run a fleet audit. That is `/repo-fleet-hygiene:audit`. `check` validates config only; it never
  walks the fleet.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor any machine-local
  state. The config is the consumer's own tracked file.
- Touch Git remotes, branches, or worktrees.

## Gotchas

- **Absolute paths in tracked config can be rejected by consumer write guards.** A root, repository, or
  canonical target written as an absolute path may trip a consumer's write-time path-portability guard;
  the same target written relative to the config file's directory passes and resolves identically, so
  `apply` prefers the relative form, except across Windows volumes, where no relative form exists and
  the absolute path is the only honest option. When that happens, write the absolute path, say in the
  report that no relative path exists between volumes, and name the consumer's remedies if the guard
  still rejects the write: colocate the config with the fleet root on one volume, exempt this file or
  path from the guard, or keep a user-global config outside the guard's scan. Do not fabricate a
  relative path or leave the consumer to conclude they misconfigured something.
- **A project-scoped config is consumed only from its own project.** Per the Scoping rule above, a
  config meant to apply from every project belongs at the user-global
  `~/.claude/repo-fleet-hygiene.conf`, not a per-project path. Otherwise the audit silently narrows to
  the project it was authored in. Two cases collapse this warning, and `check` should say which one
  applies rather than repeating a caution that cannot bite: when the project directory *is* the home
  directory both rungs name the same file, and when no project directory reaches the audit (the
  session did not supply one) the project rung is unreachable outright, leaving the
  user-global path the only one that can be consumed.
- **Config-supplied scope is additive to the audit's CLI scope.** A configured root is walked even
  when the audit is invoked with an explicit `--repo`, so a persisted fleet config widens every later
  run. The audit's `Scope:` header line names each contributing rung; a consumed config cannot be
  suppressed for a single run.
