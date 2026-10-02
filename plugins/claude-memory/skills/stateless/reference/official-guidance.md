# Official Claude Code Guidance on Auto Memory State

Each section states what this skill does, in our words, and points at the section of the official
page that covers the topic. Read the page there for its wording; this file stores none of it.

Last researched: 2026-07-22; the claude-directory, settings and cli-reference pointers verified
2026-08-10 (the other sources below were not re-checked on that date)
Sources: [memory](https://code.claude.com/docs/en/memory),
[settings](https://code.claude.com/docs/en/settings),
[env-vars](https://code.claude.com/docs/en/env-vars),
[claude-directory](https://code.claude.com/docs/en/claude-directory),
[cli-reference](https://code.claude.com/docs/en/cli-reference)

Refresh this file from current official docs before relying on it (re-fetch every source listed
above).

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
`/claude-memory:audit` skill owns that instruction layer).

- **Pointer**: [Auto memory](https://code.claude.com/docs/en/memory#auto-memory).

## Enable / disable

This skill treats auto memory as on by default, toggled by `/memory` (which writes
`autoMemoryEnabled` to user settings), settable per project through `autoMemoryEnabled` in that
project's settings, and disabled by `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, either as an OS environment
variable or in a settings file's `env` block. With `autoMemoryEnabled: false`, it treats the
auto-memory directory as neither read nor written.

- **Pointer**: [Enable or disable auto memory](https://code.claude.com/docs/en/memory#enable-or-disable-auto-memory)
  and [`autoMemoryEnabled`](https://code.claude.com/docs/en/settings-reference#automemoryenabled).

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
  [Environment variables](https://code.claude.com/docs/en/env-vars).

## Storage location

This skill resolves the default store as `~/.claude/projects/<project>/memory/`, with `<project>`
derived from the repository (every worktree and subdirectory of one repository shares one
directory) and from the project root outside a repository. It reads `autoMemoryDirectory` at every
settings scope (user, project, local, policy, `--settings`), accepts only an absolute or `~/`
path, and honors a project or local value only once the folder's workspace trust dialog is
accepted.

- **Pointer**: [Storage location](https://code.claude.com/docs/en/memory#storage-location) and
  [`autoMemoryDirectory`](https://code.claude.com/docs/en/settings-reference#automemorydirectory).

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
  [Environment variables](https://code.claude.com/docs/en/env-vars), and
  [claude-directory](https://code.claude.com/docs/en/claude-directory#explore-the-directory).

The directory holds a `MEMORY.md` index plus topic files; the layout is in the Storage location section.

This skill treats every file there as plain markdown a person may edit or delete. There is no
auto-memory-only built-in command, so selective deletion is manual removal of these files.
`claude project purge` deletes the store only as part of the full per-project wipe (see "Out of
scope" below).

- **Pointer**: [Storage location](https://code.claude.com/docs/en/memory#storage-location) and
  [Audit and edit your memory](https://code.claude.com/docs/en/memory#audit-and-edit-your-memory).

## Settings scopes and precedence

This skill resolves settings highest first: managed settings, command-line arguments, local project
settings (`.claude/settings.local.json`), shared project settings (`.claude/settings.json`), user
settings (`~/.claude/settings.json`). It treats a managed value as overriding every lower scope.
The managed-precedence exceptions are many and are read on the page; none of them names
`autoMemoryEnabled`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, or auto memory at all (checked
2026-08-10), so no lower settings scope overrides a managed `autoMemoryEnabled` value. That
negative governs settings scopes only: the `CLAUDE_CODE_DISABLE_AUTO_MEMORY` environment variable
sits outside settings precedence and, when set, still overrides the effective value, managed or not
(see "Precedence: the env var overrides the setting" above).

Managed settings live outside the repo (macOS `/Library/Application Support/ClaudeCode/`,
Linux/WSL `/etc/claude-code/`, Windows registry `HKLM`/`HKCU\SOFTWARE\Policies\ClaudeCode`).

So `CLAUDE_CODE_DISABLE_AUTO_MEMORY` can be set as a real OS environment variable **or** inside a
settings file's `env` block, which applies to every session and the subprocesses it spawns.

- **Pointer**: [Settings precedence](https://code.claude.com/docs/en/settings#settings-precedence),
  [Exceptions to managed settings precedence](https://code.claude.com/docs/en/settings#exceptions-to-managed-settings-precedence),
  and [`env`](https://code.claude.com/docs/en/settings-reference#env).
- **As of**: 2026-08-10

## Out of scope for this skill (verified, deliberate)

- **Transcripts / history / shell snapshots / sessions.** This skill treats transcripts and shell
  snapshots as cleaned at startup by `cleanupPeriodDays` (default 30, minimum 1), and the other two
  as not: `history.jsonl` persists until deleted, and `sessions/` is cleared per session rather
  than by age. Purging any of them is a different concern. The official per-project wipe is
  `claude project purge`; read its deletion plan and flags on the page.

  We read the age-based sweep as covering per-session data files (transcripts, `shell-snapshots/`,
  `debug/`, `tasks/`, `file-history/` and similar), not the `sessions/` directory, which holds one
  file per running session, removed when that session exits, with crash leftovers cleared on the
  next launch. `history.jsonl` sits among the paths kept until deleted.

  - **Pointer**: [`cleanupPeriodDays`](https://code.claude.com/docs/en/settings-reference#cleanupperioddays),
    [Cleaned up automatically](https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically),
    [Kept until you delete them](https://code.claude.com/docs/en/claude-directory#kept-until-you-delete-them).
  - **As of**: 2026-08-10

  This skill treats `claude project purge` as deleting, for one project, the transcripts and auto
  memory under `projects/`, its per-session `tasks/`, `debug/` and `file-history/` entries, its
  prompt lines in `history.jsonl`, and its entry in `~/.claude.json`; as leaving `shell-snapshots/`
  and `backups/` alone, with a warning, since they are not project-scoped; and as printing its full
  deletion plan and asking for confirmation before removing anything. The docs give the command no
  version requirement, so do not state a version floor for it. `sessions/` appears nowhere in the
  deletion list. That is this plugin's reading of that list, not a separate upstream statement.

  - **Pointer**: [Clear local data](https://code.claude.com/docs/en/claude-directory#clear-local-data)
    and [CLI commands](https://code.claude.com/docs/en/cli-reference#cli-commands).
  - **As of**: 2026-08-10

  We record `CLAUDE_CODE_SKIP_PROMPT_HISTORY` as the true "no session persistence" lever, since it
  stops transcripts and prompt history being written, and the complement to deleting the files
  after the fact. Recorded for that contrast; this skill acts on neither. Pointer:
  [Plaintext storage](https://code.claude.com/docs/en/claude-directory#plaintext-storage).

- **Claude Desktop / claude.ai account memory.** That is a server-side account store, not
  local files, so this skill cannot delete it and only gives direction (see
  [../context/desktop.md](../context/desktop.md)).

- **Subagent auto memory.** A subagent's `memory` field points at its own separate
  directory; this skill governs the main conversation's auto-memory store.
