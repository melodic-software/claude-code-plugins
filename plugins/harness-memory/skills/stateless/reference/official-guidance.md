# Official Claude Code Guidance on Auto Memory State

Each section states what this skill does, in our words, and points at the section of the official
page that covers the topic. Read the page there for its wording; this file stores none of it.

Last researched: 2026-07-22; the claude-directory, settings and cli-reference pointers verified
2026-08-10 (the other sources below were not re-checked on that date)
Sources: [Auto memory](https://code.claude.com/docs/en/memory#auto-memory),
[Settings precedence](https://code.claude.com/docs/en/settings#settings-precedence),
[env-vars](https://code.claude.com/docs/en/env-vars) (its rows carry no section anchors),
[Explore the directory](https://code.claude.com/docs/en/claude-directory#explore-the-directory),
[CLI commands](https://code.claude.com/docs/en/cli-reference#cli-commands). Each section below
names the exact section it rests on.

- **As of**: 2026-10-11 (the four anchored sources above confirmed live on their pages)
- **Recheck trigger**: one of those four pages renames, moves or drops the section its anchor
  names, or the env-vars page gains row anchors.

Refresh this file from current official docs before relying on it (re-fetch the section each
pointer below names).

**Recheck trigger:** re-derive every decision below when any of these becomes observable: the
`/memory` command gains, loses or renames its auto-memory toggle; the `autoMemoryEnabled` setting
or the `CLAUDE_CODE_DISABLE_AUTO_MEMORY` environment variable changes name, default or semantics;
the per-project memory path under `~/.claude/projects/<project>/memory/` moves; or any of the five
source pages above changes its auto-memory section. A Claude Code release note touching memory,
settings or the CLI reference is the usual way one of these surfaces. The dates above record when
the decisions last matched their sources and confer no standing authority on their own.

---

## What auto memory is

This skill governs only the notes Claude writes for itself across sessions (auto memory), never
CLAUDE.md / CLAUDE.local.md / `.claude/rules/`, which **you** write (the sibling
`/harness-memory:audit` skill owns that instruction layer).

- **Pointer**: [Auto memory](https://code.claude.com/docs/en/memory#auto-memory).

## Enable / disable

This skill treats auto memory as on unless a setting or the environment variable turns it off,
and reads at the pointer which sessions start with it off, where the `/memory` toggle saves, and
where the toggle cannot turn it back on. It reads `autoMemoryEnabled` at every settings scope and
`CLAUDE_CODE_DISABLE_AUTO_MEMORY` both as an OS environment variable and in a settings file's `env`
block. With `autoMemoryEnabled: false`, it treats the auto-memory directory as neither read nor
written.

- **Pointer**: [Enable or disable auto memory](https://code.claude.com/docs/en/memory#enable-or-disable-auto-memory)
  and [`autoMemoryEnabled`](https://code.claude.com/docs/en/settings-reference#automemoryenabled).
- **As of**: 2026-10-11
- **Recheck trigger**: the section changes the default, which sessions default off, or where the
  toggle saves.

### Precedence: the env var overrides the setting (VERIFIED)

When the env var is set (to `0` or `1`), this skill treats it as **overriding**
`autoMemoryEnabled`: `=1` disables, `=0` forces auto memory on even against
`autoMemoryEnabled: false` or `--bare` mode. When the env var is unset, `autoMemoryEnabled`
(resolved by settings precedence) governs. `status` reports the env var as authoritative whenever it
is set. A set env var of `0` alongside `autoMemoryEnabled: false` means auto memory is effectively
**on**. `disable` sets the env var to `1` (the strong, authoritative lever) and
`autoMemoryEnabled: false` together, so the state is unambiguous and survives the env var later
being unset.

- **Pointer**: the `CLAUDE_CODE_DISABLE_AUTO_MEMORY` row of
  [Environment variables](https://code.claude.com/docs/en/env-vars) (rows carry no anchor), and
  [Enable or disable auto memory](https://code.claude.com/docs/en/memory#enable-or-disable-auto-memory),
  the nearest section naming the variable.
- **As of**: 2026-10-11
- **Recheck trigger**: the env-vars row or that section changes what a set value of the variable
  does, or whether it outranks `autoMemoryEnabled`.

## Storage location

This skill, and the sibling `audit` skill through the shared `resolve-memory-dir.sh`, resolve the
default store as the per-project `memory/` directory under the config root's `projects/` tree,
one directory per repository. They read `autoMemoryDirectory` at every settings scope the page
names, and apply the page's rules for which values are valid and when a project or local value is
honored. How `<project>` is derived, the path forms accepted and the trust and read-blocking
conditions are read at the pointer.

- **Pointer**: [Storage location](https://code.claude.com/docs/en/memory#storage-location) and
  [`autoMemoryDirectory`](https://code.claude.com/docs/en/settings-reference#automemorydirectory).
- **As of**: 2026-10-11
- **Recheck trigger**: the section changes how the project directory is derived or named, the
  scopes `autoMemoryDirectory` is read from, the accepted path forms, or when a repository-supplied
  value is honored.

**What `purge` depends on:** because `autoMemoryDirectory` is read from *any* scope, the
real memory dir may not be the slug-derived default. Purge must read that key at every scope
before it enumerates what to delete, or it can miss (and fail to purge) a relocated store.

### CLAUDE_CONFIG_DIR relocates the whole config root

This skill resolves the config root as `${CLAUDE_CONFIG_DIR:-~/.claude}` (`~/.claude` is
`%USERPROFILE%\.claude` on Windows): when the env var is set, the user `settings.json` and the
`projects/<project>/memory/` tree both live under it. Every scope and memory-dir resolution in this
skill (the `scope-report.sh` snapshot, the shared `resolve-memory-dir.sh`, and the disable/purge
workflows) resolves the config root this way, so a relocated root is honored rather than mistaken
for an `autoMemoryDirectory` override.

- **Pointer**: the `CLAUDE_CONFIG_DIR` row of
  [Environment variables](https://code.claude.com/docs/en/env-vars) (rows carry no anchor),
  [Storage location](https://code.claude.com/docs/en/memory#storage-location), the nearest section
  naming the variable, and
  [claude-directory](https://code.claude.com/docs/en/claude-directory#explore-the-directory).
- **As of**: 2026-10-11
- **Recheck trigger**: the env-vars row or either section changes what the variable relocates.

The directory holds a `MEMORY.md` index plus topic files; the layout is in the Storage location section.

This skill treats every file there as plain markdown a person may edit or delete. There is no
auto-memory-only built-in command, so selective deletion is manual removal of these files.
`claude purge` deletes the store only as part of the full per-project wipe (see "Out of
scope" below).

- **Pointer**: [Storage location](https://code.claude.com/docs/en/memory#storage-location) and
  [Audit and edit your memory](https://code.claude.com/docs/en/memory#audit-and-edit-your-memory).

## Settings scopes and precedence

This skill resolves settings in the precedence order the page lists, highest first, reading the
order there rather than from this file. It treats a managed value as overriding every lower scope.
The managed-precedence exceptions are many and are read on the page; none of them names
`autoMemoryEnabled`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, or auto memory at all (checked
2026-10-11), so no lower settings scope overrides a managed `autoMemoryEnabled` value. That
negative governs settings scopes only: the `CLAUDE_CODE_DISABLE_AUTO_MEMORY` environment variable
sits outside settings precedence and, when set, still overrides the effective value, managed or not
(see "Precedence: the env var overrides the setting" above).

Managed settings live outside the repository, in system locations and, on some platforms, in OS
policy stores such as the Windows registry that this skill's scripts do not read; each location is
read at
[Where each mechanism stores the policy](https://code.claude.com/docs/en/managed-settings#where-each-mechanism-stores-the-policy)
(as of 2026-10-11; recheck when that section adds, moves or drops a location).

So `CLAUDE_CODE_DISABLE_AUTO_MEMORY` can be set as a real OS environment variable **or** inside a
settings file's `env` block, which applies to every session and the subprocesses it spawns.

- **Pointer**: [Settings precedence](https://code.claude.com/docs/en/settings#settings-precedence),
  [Exceptions to managed settings precedence](https://code.claude.com/docs/en/settings#exceptions-to-managed-settings-precedence),
  and [`env`](https://code.claude.com/docs/en/settings-reference#env).
- **As of**: 2026-10-11
- **Recheck trigger**: the settings page adds, removes or reorders a level in the precedence list,
  or documents a managed-settings exception for `env` or for auto memory.

## Out of scope for this skill (verified, deliberate)

- **Transcripts / history / shell snapshots / sessions.** This skill treats transcripts and shell
  snapshots as cleaned at startup by `cleanupPeriodDays` (its default and minimum are read at the
  pointer), and the other two
  as not: `history.jsonl` persists until deleted, and `sessions/` is cleared per session rather
  than by age. Purging any of them is a different concern. The official per-project wipe is
  `claude purge`; read its deletion plan and flags on the page.

  We read the age-based sweep as covering per-session data files (transcripts, `shell-snapshots/`,
  `debug/`, `tasks/`, `file-history/` and similar), not the `sessions/` directory, which holds one
  file per running session, removed when that session exits, with crash leftovers cleared on the
  next launch. `history.jsonl` sits among the paths kept until deleted.

  - **Pointer**: [`cleanupPeriodDays`](https://code.claude.com/docs/en/settings-reference#cleanupperioddays),
    [Cleaned up automatically](https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically),
    [Kept until you delete them](https://code.claude.com/docs/en/claude-directory#kept-until-you-delete-them).
  - **As of**: 2026-10-11
  - **Recheck trigger**: either claude-directory section moves a path between the cleaned and kept
    lists, or the `cleanupPeriodDays` default or minimum changes.

  This skill names `claude purge` as the official per-project wipe, and treats it as confirming
  before it deletes and as covering auto memory along with other per-project data. When a user
  needs its scope (what it deletes, what it leaves alone and why), this skill reads it from the
  pointer at the time, never from this file or from memory. `sessions/` appears nowhere in the
  page's deletion list. That is this plugin's reading of that list, not a separate upstream
  statement. The command was renamed; when a user's Claude Code rejects `claude purge`, give the
  former name the page records, never one from memory.

  - **Pointer**: when stating the command's name, arguments or flags, fetch
    [CLI commands](https://code.claude.com/docs/en/cli-reference#cli-commands) live; for what it
    deletes and its former name, fetch
    [Clear local data](https://code.claude.com/docs/en/claude-directory#clear-local-data).
  - **As of**: 2026-10-10
  - **Recheck trigger**: the Clear local data section changes what `claude purge` deletes or keeps,
    or the CLI commands table renames or drops the command.

  **Source conflict**: the changelog v2.1.288 entry and
  [Clear local data](https://code.claude.com/docs/en/claude-directory#clear-local-data) disagree on
  whether the former command name still runs. This skill never tells a user it is gone.

  - **Pointer**: when a user asks whether the former name still works, fetch the
    [changelog](https://code.claude.com/docs/en/changelog) (v2.1.288) and
    [Clear local data](https://code.claude.com/docs/en/claude-directory#clear-local-data) live.
  - **As of**: 2026-10-10
  - **Recheck trigger**: either source changes what it says about the former command name.

  We record `CLAUDE_CODE_SKIP_PROMPT_HISTORY` as the true "no session persistence" lever, since it
  stops transcripts and prompt history being written, and the complement to deleting the files
  after the fact. Recorded for that contrast; this skill acts on neither. Pointer:
  [Plaintext storage](https://code.claude.com/docs/en/claude-directory#plaintext-storage).

- **Claude Desktop / claude.ai account memory.** That is a server-side account store, not
  local files, so this skill cannot delete it and only gives direction (see
  [../context/desktop.md](../context/desktop.md)).

- **Subagent auto memory.** A subagent's `memory` field points at its own separate
  directory; this skill governs the main conversation's auto-memory store.
