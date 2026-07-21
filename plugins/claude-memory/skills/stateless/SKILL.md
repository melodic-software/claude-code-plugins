---
name: stateless
description: "Inspect and turn off Claude Code's auto memory — the notes Claude writes itself per repo under ~/.claude/projects/<project>/memory/. Use when: 'make Claude stateless', 'stop Claude remembering', 'disable auto memory', 'turn off auto-memory', 'purge/clear/delete auto memory', 'wipe what Claude saved about this repo', 'does Claude have saved memories'. Actions: status (default — memory + settings across all scopes), disable (autoMemoryEnabled:false + CLAUDE_CODE_DISABLE_AUTO_MEMORY), purge (destructive delete, confirm-gated). Auto-memory only — not CLAUDE.md/rules (use /claude-memory:audit) and not transcripts/history."
argument-hint: "[status|disable|purge] — default: status"
user-invocable: true
disable-model-invocation: false
---

## Auto-memory snapshot

```!
bash "${CLAUDE_PLUGIN_ROOT}/skills/stateless/scripts/scope-report.sh" || echo "(snapshot unavailable — run the scope-report script manually)"
```

# Stateless

Inspect and disable Claude Code **auto memory** — the store Claude writes for itself, one
directory per repo (`~/.claude/projects/<project>/memory/`, relocatable via
`autoMemoryDirectory`). Governs auto-memory only. Not in scope: CLAUDE.md / CLAUDE.local.md /
`.claude/rules/` (use `/claude-memory:audit`), transcripts, history, or shell snapshots.

Criteria and exact doc quotes live in [reference/official-guidance.md](reference/official-guidance.md);
re-fetch the two source pages if a fact is load-bearing before you act.

## Scope

| Entity | Location | This skill |
|--------|----------|-----------|
| Auto-memory store | `~/.claude/projects/<project>/memory/` (or `autoMemoryDirectory`) | Yes — status / disable / purge |
| `autoMemoryEnabled` setting | any settings scope | Yes — reads & writes |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | OS env or settings `env` block | Yes — reads & writes |
| CLAUDE.md / CLAUDE.local.md / `.claude/rules/` | repo + user | No — use `/claude-memory:audit` |
| Transcripts / history / sessions / snapshots | `~/.claude/...` | No — auto-cleaned by `cleanupPeriodDays` |
| Claude Desktop / claude.ai memory | server-side account | Direction only — [context/desktop.md](context/desktop.md) |

## Argument parsing

| Argument | Action |
|----------|--------|
| *(none)* or `status` | Report the auto-memory posture: effective enabled/disabled state, where the store lives, what it holds. Read-only. |
| `disable` | Turn auto memory off durably (`autoMemoryEnabled: false` + `CLAUDE_CODE_DISABLE_AUTO_MEMORY`). Edits settings — confirm scope first. |
| `purge` | **Destructive.** Delete the auto-memory files. Reads `autoMemoryDirectory` at every scope first, shows a manifest, and deletes only after explicit confirmation. |

## Precedence (documented)

`CLAUDE_CODE_DISABLE_AUTO_MEMORY` **overrides** `autoMemoryEnabled`: per the env-vars doc, `=1`
disables and `=0` forces auto memory *on* even when `autoMemoryEnabled: false` would disable
it. When the env var is unset, `autoMemoryEnabled` (by settings precedence) governs. So a set
env var of `0` alongside `autoMemoryEnabled: false` means auto memory is effectively **on** —
`status` must report the env var as authoritative whenever it is set. `disable` sets the env
var to `1` (the authoritative lever) and `autoMemoryEnabled: false` together. See the
reference file's "Precedence: the env var overrides the setting (VERIFIED)".

## Actions

- **status** (default): load [context/status.md](context/status.md).
- **disable**: load [context/disable.md](context/disable.md).
- **purge**: load [context/purge.md](context/purge.md).

For the Claude Desktop / claude.ai account store (server-side, not local files), load
[context/desktop.md](context/desktop.md) — relevant to `status` and `purge` whenever the user
wants to be stateless everywhere, not just in this repo.

## Gotchas

- **Precedence**: `CLAUDE_CODE_DISABLE_AUTO_MEMORY` overrides `autoMemoryEnabled` (`=0` forces
  on even against `autoMemoryEnabled: false`). A set env var is authoritative in `status`. (See above.)
- **`autoMemoryDirectory` relocates the store** and is read from *any* scope. The snapshot
  prints the slug-derived default only — `purge` and `status` must read the override at every
  scope or they act on the wrong directory.
- **`CLAUDE_CONFIG_DIR` relocates the whole config root**: when set, the user `settings.json`
  *and* the `projects/<project>/memory/` tree live under it, not `~/.claude`. All scope and
  memory-dir resolution honors `${CLAUDE_CONFIG_DIR:-~/.claude}` (scripts + workflows); the
  snapshot reports the resolved root, and `purge`'s relocation check treats it as expected.
- **Windows managed policy** can live in the registry (`HKLM`/`HKCU\SOFTWARE\Policies\ClaudeCode`),
  not a file. `scope-report.sh` can't read it — report managed scope as unread, don't assume empty.
- **`disable` applies next session**, not immediately: the setting and `env` block are read at
  startup. Tell the user to restart / start a new session.
- **Tracked `settings.json`**: a live edit to a dotfile-manager-tracked settings file must be
  backfilled to the source; never run an `apply` that could revert the edit.
- **Desktop / claude.ai memory is server-side** — `purge` cannot delete it; give direction only.

## Repo-agnostic contract

Discover the consumer's state at runtime — never hardcode a machine's paths or current
posture. Settings scopes, the memory directory, and the env var are read fresh from the
snapshot above and the workflow scripts. The bundled `scope-report.sh` reuses the plugin's
single-source memory-dir resolver (`skills/audit/scripts/resolve-memory-dir.sh`) rather than
re-implementing slug derivation.
