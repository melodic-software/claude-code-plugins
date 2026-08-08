# Official Claude Code Guidance on Auto Memory State

Last researched: 2026-07-22; code.claude.com/docs/en/claude-directory and
code.claude.com/docs/en/settings verified 2026-08-08 (the other sources below were not
re-checked on that date)
Sources: [code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory),
[code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings),
[code.claude.com/docs/en/env-vars](https://code.claude.com/docs/en/env-vars),
[code.claude.com/docs/en/claude-directory](https://code.claude.com/docs/en/claude-directory)

Refresh this file from current official docs before relying on it (re-fetch every source listed
above).

---

## What auto memory is

> "Auto memory lets Claude accumulate knowledge across sessions without you writing
> anything. Claude saves notes for itself as it works: build commands, debugging insights,
> architecture notes, code style preferences, and workflow habits."
> — code.claude.com/docs/en/memory

Distinct from CLAUDE.md (which **you** write). This skill governs only the Claude-written
auto-memory store — not CLAUDE.md / CLAUDE.local.md / `.claude/rules/` (the sibling
`/claude-memory:audit` skill owns that instruction layer).

## Enable / disable

> "Auto memory is on by default. To toggle it, open `/memory` in a session and use the auto
> memory toggle, which saves `autoMemoryEnabled` to your user settings at
> `~/.claude/settings.json`. To turn it off for a single project, set `autoMemoryEnabled` in
> that project's settings"
> — code.claude.com/docs/en/memory

> "To disable auto memory via environment variable, set `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`."
> — code.claude.com/docs/en/memory

> "When `false`, Claude does not read from or write to the auto memory directory. You can
> also toggle this with `/memory` during a session. To disable via environment variable, set
> `CLAUDE_CODE_DISABLE_AUTO_MEMORY` in `env`"
> — code.claude.com/docs/en/settings (`autoMemoryEnabled` description)

### Precedence: the env var overrides the setting (VERIFIED)

> "`CLAUDE_CODE_DISABLE_AUTO_MEMORY` | Set to `1` to disable auto memory. Set to `0` to force
> auto memory on even when `--bare` mode or `autoMemoryEnabled: false` would otherwise disable
> it. When disabled, Claude does not create or load auto memory files"
> — code.claude.com/docs/en/env-vars

So when the env var is set (to `0` or `1`), it **overrides** `autoMemoryEnabled` — `=1`
disables, `=0` forces on even against `autoMemoryEnabled: false`. When the env var is unset,
`autoMemoryEnabled` (resolved by settings precedence) governs. `status` reports the env var as
authoritative whenever it is set — a set env var of `0` alongside `autoMemoryEnabled: false`
means auto memory is effectively **on**. `disable` sets the env var to `1` (the strong,
authoritative lever) and `autoMemoryEnabled: false` together, so the state is unambiguous and
survives the env var later being unset.

## Storage location

> "Each project gets its own memory directory at `~/.claude/projects/<project>/memory/`. The
> `<project>` path is derived from the git repository, so all worktrees and subdirectories
> within the same repo share one auto memory directory. Outside a git repo, the project root
> is used instead."
> — code.claude.com/docs/en/memory

> "To store auto memory in a different location, set `autoMemoryDirectory` in your
> `settings.json`. It is read from any settings scope: user, project, local, policy, or
> `--settings`. ... The value must be an absolute path or start with `~/`. When set in a
> project's `.claude/settings.json` or `.claude/settings.local.json`, the value is honored
> only after you accept the workspace trust dialog for that folder"
> — code.claude.com/docs/en/memory

**Load-bearing for `purge`:** because `autoMemoryDirectory` is read from *any* scope, the
real memory dir may not be the slug-derived default. Purge must read that key at every scope
before it enumerates what to delete, or it can miss (and fail to purge) a relocated store.

### CLAUDE_CONFIG_DIR relocates the whole config root

> "On Windows, `~/.claude` resolves to `%USERPROFILE%\.claude`. If you set `CLAUDE_CONFIG_DIR`,
> every `~/.claude` path on this page lives under that directory instead."
> — code.claude.com/docs/en/claude-directory (the page scopes settings AND memory under `~/.claude`)

So the config root is `${CLAUDE_CONFIG_DIR:-~/.claude}`: when the env var is set, the user
`settings.json` and the `projects/<project>/memory/` tree both live under it. Every scope and
memory-dir resolution in this skill (the `scope-report.sh` snapshot, the shared
`resolve-memory-dir.sh`, and the disable/purge workflows) resolves the config root this way, so
a relocated root is honored rather than mistaken for an `autoMemoryDirectory` override.

The directory holds a `MEMORY.md` index plus optional topic files (layout per
code.claude.com/docs/en/memory):

```text
~/.claude/projects/<project>/memory/
├── MEMORY.md          # Concise index, loaded into every session
├── debugging.md       # Detailed notes on debugging patterns
├── api-conventions.md # API design decisions
└── ...                # Any other topic files Claude creates
```

> "Auto memory files are plain markdown you can edit or delete at any time."
> — code.claude.com/docs/en/memory

There is no auto-memory-only built-in command — selective deletion is manual removal of these
files. `claude project purge` (v2.1.124+) deletes the store only as part of the full
per-project wipe (see "Out of scope" below).

## Settings scopes and precedence

> "Settings apply in order of precedence. From highest to lowest:
>
> 1. **Managed settings** (server-managed, MDM/OS-level policies, or managed settings)
> 2. **Command line arguments**
> 3. **Local project settings** (`.claude/settings.local.json`)
> 4. **Shared project settings** (`.claude/settings.json`)
> 5. **User settings** (`~/.claude/settings.json`)"
> — code.claude.com/docs/en/settings (verified 2026-08-08; each item's nested detail bullets are
> omitted, and item 1's three parenthetical links are flattened to their labels)

> "Cannot be overridden by any other level, including command line arguments, apart from the
> exceptions in the bullets below"
> — code.claude.com/docs/en/settings (a nested bullet under item 1, verified 2026-08-08)

Item 1's exception bullets are longer and more varied than this file summarizes — read them on the
page. What matters here is a negative: none of them names `autoMemoryEnabled`,
`CLAUDE_CODE_DISABLE_AUTO_MEMORY`, or auto memory at all (verified 2026-08-08), so no ordinary
lower scope overrides a managed auto-memory value.

Managed settings live outside the repo (macOS `/Library/Application Support/ClaudeCode/`,
Linux/WSL `/etc/claude-code/`, Windows registry `HKLM`/`HKCU\SOFTWARE\Policies\ClaudeCode`).

> "Environment variables applied to every session and to subprocesses Claude Code spawns from
> it."
> — code.claude.com/docs/en/settings (the `env` setting's description, first sentence; verified
> 2026-08-08)

So `CLAUDE_CODE_DISABLE_AUTO_MEMORY` can be set as a real OS environment variable **or**
inside a settings file's `env` block; the docs bless the `env`-block form explicitly.

## Out of scope for this skill (verified, deliberate)

- **Transcripts / history / shell snapshots / sessions.** Transcripts and shell snapshots are
  auto-cleaned at startup by `cleanupPeriodDays` (default 30, minimum 1). The other two are
  not: `history.jsonl` persists until deleted, and `sessions/` is cleared per session rather
  than by age. Purging any of them is a different concern — the official per-project wipe is
  `claude project purge`, quoted in full below (the deletion plan and flags live in the doc,
  not here).
  > "**Default**: `30` days, minimum `1`. Claude Code deletes session files and other
  > application data older than this period at startup."
  > — code.claude.com/docs/en/settings (the `cleanupPeriodDays` setting's description, first two
  > sentences; verified 2026-08-08)

  Read "session files" there as per-session data files, not the `sessions/` directory: the page
  links that phrase to claude-directory's "Cleaned up automatically" table, whose rows are the
  transcript, `shell-snapshots/`, `debug/`, `tasks/`, `file-history/`, and similar per-session
  artifacts. `sessions/` is not a row in that table, and the same page says so directly two
  quotes down.

  > "The following paths are not covered by automatic cleanup and persist indefinitely."
  > — code.claude.com/docs/en/claude-directory, heading the table whose first row is
  > `history.jsonl` (verified 2026-08-08)

  > "`sessions/` holds one small file per running session, used to detect concurrent sessions
  > and crashes. It isn't part of the age-based sweep: Claude Code removes each file when its
  > session exits and clears crash leftovers on the next launch."
  > — code.claude.com/docs/en/claude-directory (verified 2026-08-08)

  > "Run `claude project purge` to delete the state Claude Code holds for one project. It
  > deletes:
  >
  > - Transcripts and auto memory under `projects/`
  > - Per-session `tasks/`, `debug/`, and `file-history/` entries
  > - Matching prompt lines in `history.jsonl`
  > - The project's entry in `~/.claude.json`"
  > — code.claude.com/docs/en/claude-directory (verified 2026-08-08)

  As of that check the page no longer carries its "requires Claude Code v2.1.124 or later"
  sentence, and neither does cli-reference. The `v2.1.124+` floor this plugin still states is
  therefore a retained claim with no current upstream source — treat it as a lower bound to
  re-source, not as doc-backed.

  What it leaves alone, from the same page:

  > "The command leaves `shell-snapshots/` and `backups/` alone because those are not
  > project-scoped, and warns about them in the plan output."
  > — code.claude.com/docs/en/claude-directory (verified 2026-08-08)

  `sessions/` appears nowhere in the deletion list above — this plugin's reading of that list,
  not a separate upstream statement.

  It also does not delete unprompted:

  > "The command prints the full deletion plan and asks for confirmation before removing
  > anything."
  > — code.claude.com/docs/en/claude-directory (verified 2026-08-08)

  `CLAUDE_CODE_SKIP_PROMPT_HISTORY` skips "writing transcripts and prompt history in any mode"
  (code.claude.com/docs/en/claude-directory) — the true "no session persistence" lever, and the
  complement to deleting the files after the fact. Recorded for that contrast; this skill acts
  on neither.

- **Claude Desktop / claude.ai account memory.** That is a server-side account store, not
  local files — this skill cannot delete it and only gives direction (see
  [../context/desktop.md](../context/desktop.md)).

- **Subagent auto memory.** A subagent's `memory` field points at its own separate
  directory; this skill governs the main conversation's auto-memory store.
