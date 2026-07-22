# Official Claude Code Guidance on Auto Memory State

Last researched: 2026-07-22
Sources: [code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory),
[code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings),
[code.claude.com/docs/en/env-vars](https://code.claude.com/docs/en/env-vars)

Refresh this file from current official docs before relying on it (re-fetch both pages).

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

There is no built-in purge command — deletion is manual removal of these files.

## Settings scopes and precedence

> "1. Managed (highest priority) — cannot be overridden 2. Command-line arguments 3. Local
> (`.claude/settings.local.json`) 4. Project (`.claude/settings.json`) 5. User
> (`~/.claude/settings.json`) — lowest priority"
> — code.claude.com/docs/en/settings

Managed settings live outside the repo (macOS `/Library/Application Support/ClaudeCode/`,
Linux/WSL `/etc/claude-code/`, Windows registry `HKLM`/`HKCU\SOFTWARE\Policies\ClaudeCode`).

> "Environment variables defined in the `settings.json` `env` object are applied to every
> session and passed to all subprocesses Claude Code spawns."
> — code.claude.com/docs/en/settings

So `CLAUDE_CODE_DISABLE_AUTO_MEMORY` can be set as a real OS environment variable **or**
inside a settings file's `env` block; the docs bless the `env`-block form explicitly.

## Out of scope for this skill (verified, deliberate)

- **Transcripts / history / shell snapshots / sessions.** Session files are auto-cleaned at
  startup by `cleanupPeriodDays` (default 30, minimum 1). Purging those is a different
  concern and is deferred to a future skill.
  > "cleanupPeriodDays ... Default: 30 days (minimum: 1) ... Age threshold for deleting
  > session files and application data at startup"
  > — code.claude.com/docs/en/settings

  `CLAUDE_CODE_SKIP_PROMPT_HISTORY` disables transcript writes entirely — the true
  "no session persistence" lever, recorded here for that future skill, not acted on by this one.

- **Claude Desktop / claude.ai account memory.** That is a server-side account store, not
  local files — this skill cannot delete it and only gives direction (see
  [../context/desktop.md](../context/desktop.md)).

- **Subagent auto memory.** A subagent's `memory` field points at its own separate
  directory; this skill governs the main conversation's auto-memory store.
