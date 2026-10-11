---
description: "Inspect and turn off Claude Code's auto memory, the notes Claude writes itself per repo under ~/.claude/projects/PROJECT/memory/. Use when: 'make Claude stateless', 'stop Claude remembering', 'disable auto memory', 'turn off auto-memory', 'purge/clear/delete auto memory', 'wipe what Claude saved about this repo', 'does Claude have saved memories'. Actions: status (default, memory + settings across all scopes), disable (autoMemoryEnabled:false + CLAUDE_CODE_DISABLE_AUTO_MEMORY), purge (destructive delete, confirm-gated). Auto-memory only, not CLAUDE.md/rules (use /harness-memory:audit) and not transcripts/history."
argument-hint: "[status|disable|purge]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Inspect, disable, or purge Claude Code's per-repo auto memory
---

**Arguments.** `[status|disable|purge]`. Default: status

## Auto-memory snapshot

```!
bash "${CLAUDE_PLUGIN_ROOT}/skills/stateless/scripts/scope-report.sh" || echo "(snapshot unavailable — run the scope-report script manually)"
```

# Stateless

Inspect and disable Claude Code **auto memory**, the store Claude writes for itself, one
directory per repo (`~/.claude/projects/<project>/memory/`, relocatable via
`autoMemoryDirectory`). Governs auto-memory only. Not in scope: CLAUDE.md / CLAUDE.local.md /
`.claude/rules/` (use `/harness-memory:audit`), transcripts, history, or shell snapshots. For the
official full per-project wipe, use `claude purge`.
[reference/official-guidance.md](reference/official-guidance.md), "Out of scope for this skill",
records how this skill treats that command's scope; read the deletion plan and flags at
[Clear local data](https://code.claude.com/docs/en/claude-directory#clear-local-data).

[reference/official-guidance.md](reference/official-guidance.md) holds the decisions this skill
acts on, each with a pointer to its docs section and none of the docs' text; re-read the pointed-at
section before acting on a load-bearing fact.

## Scope

| Entity | Location | This skill |
|--------|----------|-----------|
| Auto-memory store | `~/.claude/projects/<project>/memory/` (or `autoMemoryDirectory`) | Yes. Status / disable / purge |
| `autoMemoryEnabled` setting | any settings scope | Yes. Reads and writes |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | OS env or settings `env` block | Yes. Reads and writes |
| CLAUDE.md / `.claude/rules/` | repo + user | No. Use `/harness-memory:audit` |
| CLAUDE.local.md | repo only, no user-scope equivalent | No. Use `/harness-memory:audit` |
| Transcripts | `~/.claude/projects/<project>/` | No. How we treat its age sweep and `claude purge`: official-guidance.md, "Out of scope for this skill" |
| Prompt history | `~/.claude/history.jsonl` | No. Same record |
| Session files | `~/.claude/sessions/` | No. Same record |
| Shell snapshots / backups | `~/.claude/shell-snapshots/`, `~/.claude/backups/` | No. Same record |
| Claude Desktop / claude.ai memory | server-side account | Direction only. See [context/desktop.md](context/desktop.md) |

## Argument parsing

| Argument | Action |
|----------|--------|
| *(none)* or `status` | Report the auto-memory posture: effective enabled/disabled state, where the store lives, what it holds. Read-only. |
| `status all` | Machine-wide: the `status` report plus a table of EVERY per-project memory store (`scripts/enumerate-all-projects.sh`). Read-only. |
| `disable` | Turn auto memory off durably (`autoMemoryEnabled: false` + `CLAUDE_CODE_DISABLE_AUTO_MEMORY`). Edits settings. Confirm scope first. |
| `purge` | **Destructive.** Delete the auto-memory files. Reads `autoMemoryDirectory` at every scope first, shows a manifest, offers an opt-in pre-delete backup, and deletes only after explicit confirmation. |
| `purge all` | **Destructive, machine-wide.** Same flow with every per-project store as the candidate set, one combined manifest, and ONE combined gate stating the total count and every directory. |

## Precedence

This skill treats `CLAUDE_CODE_DISABLE_AUTO_MEMORY` as authoritative whenever it is set: `1`
reports auto memory off, and `0` reports it **on** even against `autoMemoryEnabled: false`. Only
when the env var is unset does `autoMemoryEnabled` (by settings precedence) decide. `status` must
report the env var as authoritative whenever it is set. `disable` sets the env var to `1` and
`autoMemoryEnabled: false` together. The reference file's "Precedence: the env var overrides the
setting (VERIFIED)" holds the pointer, as-of date and recheck trigger.

## Actions

- **status** (default): load [context/status.md](context/status.md).
- **disable**: load [context/disable.md](context/disable.md).
- **purge**: load [context/purge.md](context/purge.md).

For the Claude Desktop / claude.ai account store (server-side, not local files), load
[context/desktop.md](context/desktop.md). Relevant to `status` and `purge` whenever the user
wants to be stateless everywhere, not just in this repo.

The `context/` files write each bundled script as `<skill-dir>/scripts/<name>.sh`, where
`<skill-dir>` is this skill's directory: `${CLAUDE_SKILL_DIR}`. Put that path in place of the
placeholder before running a command. We never put a `${…}` token in those files: we do not rely
on one being substituted in a file read through the Read tool, or on the Bash tool's environment
carrying `CLAUDE_PLUGIN_ROOT`.

- **Pointer**: for where each `${…}` reference resolves, see
  [Where each variable resolves](https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves).
- **As of**: 2026-10-07
- **Recheck trigger**: that table adds supporting files to where a `${…}` reference resolves.

## Boundary, the built-in `/memory` command

"Turn off auto memory" and "what has Claude saved" can land on either.

- **`/memory` (built-in command)**: the person's interactive editor for CLAUDE.md files and the
  auto-memory toggle and entries in the running session. This skill never runs it.
- **This skill (marketplace plugin).** Reports the effective auto-memory state across every
  settings scope and the env var that overrides them, disables it durably through both levers,
  and purges the store behind a manifest and a confirmation gate.

**Routing.** When the person wants a quick interactive toggle or a look at the saved entries,
offer it to the person: you can run `/memory` instead of or alongside this skill. Prefer this skill
when precedence across scopes matters, when the env var is set, or for a durable disable or a
purge. An unattended run records the offer in its output instead of asking.

**Mutation gate.** `/memory` writes whatever the person changes in its dialog; this skill never
runs it on the person's behalf. A `/memory` toggle can be overridden by `CLAUDE_CODE_DISABLE_AUTO_MEMORY`,
which `status` reports.

**Availability is never assumed.** This section states what to do when the person can run
`/memory`, never that it is present in their host. The four-part records live in
[reference/native-memory.md](reference/native-memory.md).

## Gotchas

- **Precedence**: a set `CLAUDE_CODE_DISABLE_AUTO_MEMORY` is authoritative in `status`, `0`
  included. (See above.)
- **`autoMemoryDirectory`**: we treat it as able to relocate the store from *any* scope
  (official-guidance.md, "Storage location"). The snapshot prints the slug-derived default only.
  `purge` and `status` must read the override at every scope or they act on the wrong directory.
- **`CLAUDE_CONFIG_DIR`**: we treat it as relocating the whole config root, the user
  `settings.json` *and* the `projects/<project>/memory/` tree included (official-guidance.md,
  "CLAUDE_CONFIG_DIR relocates the whole config root"). All scope and memory-dir resolution honors
  `${CLAUDE_CONFIG_DIR:-~/.claude}` (scripts + workflows); the snapshot reports the resolved root,
  and `purge`'s relocation check treats it as expected.
- **Windows managed policy**: we treat it as possibly held in the registry
  (`HKLM`/`HKCU\SOFTWARE\Policies\ClaudeCode`) rather than a file, which `scope-report.sh` can't
  read. Report managed scope as unread, don't assume empty.
- **`disable` leaves this session's loaded memory in place.** What auto memory loaded at startup
  stays in the current context whether or not the setting reloads mid-session, so tell the user a
  new session is the first one that starts without it.
  - **Pointer**: for which settings edits reach a running session, see
    <https://code.claude.com/docs/en/settings#when-edits-take-effect>; for the toggle, see
    <https://code.claude.com/docs/en/settings-reference#automemoryenabled>.
  - **As of**: 2026-10-01
  - **Recheck trigger**: either section changes whether an `autoMemoryEnabled` or `env` edit
    reaches a running session.
- **Tracked `settings.json`**: a live edit to a dotfile-manager-tracked settings file must be
  backfilled to the source; never run an `apply` that could revert the edit.
- **Desktop / claude.ai memory is server-side**. `purge` cannot delete it; give direction only.

## Repo-agnostic contract

Discover the consumer's state at runtime. Never hardcode a machine's paths or current
posture. Settings scopes, the memory directory, and the env var are read fresh from the
snapshot above and the workflow scripts. The bundled `scope-report.sh` reuses the plugin's
single-source memory-dir resolver (`skills/audit/scripts/resolve-memory-dir.sh`) rather than
re-implementing slug derivation.
