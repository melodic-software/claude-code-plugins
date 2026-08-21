# Context guard — capture channels in cloud and headless sessions

Why the statusline tee is not the only capture source, what each candidate channel does and does
not carry, and how a consumer tells a *structurally absent* instrument from a *broken* one.

`reference/reader-contract.md` remains the authoritative reader-side contract: snapshot path
pattern, staleness rule, zone bands, combination rule. This file is the **writer-side channel
inventory** — it explains where a snapshot can come from, and what to expect when none can.

## Current-state facts (measured, not inferred)

Measured **2026-08-21** inside a live Claude Code on the web container
(`CLAUDE_CODE_ENTRYPOINT=remote`, `CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE=cloud_default`,
`claude --version` → `2.1.235 (Claude Code)`).

| Observation | Command | Result |
|-------------|---------|--------|
| Is a statusline configured? | `grep -rn statusLine ~/.claude/settings.json ~/.claude/launcher-settings.json ~/.claude/remote-settings.json ~/.claude/policy-limits.json` | no match in any scope; `/etc/claude-code/managed-settings.json` does not exist |
| Does the contract directory exist? | `ls -la ~/.claude/context-guard/` | exists, containing only `context/` |
| Does a snapshot exist? | `ls -la ~/.claude/context-guard/context/` | only `<session_id>.compacted` (the `PostCompact` marker); **no `<session_id>.json`** |
| What does the resolver return? | `bash scripts/context-zone.sh <session_id>` | `unknown` |

The issue's central claim is **confirmed with one correction**: `~/.claude/context-guard/` *does*
exist here, but only because the `PostCompact` hook created it. The **snapshot** the reader needs
is absent, and the resolver prints `unknown`.

The correction matters, because it is also the finding that unblocks the fix: **plugin hooks do
run in this environment.** The `.compacted` marker in that directory was written by
`hooks/post-compact-mark.sh` during an auto-compaction of this very session. The statusline is the
only context-guard writer that is silent in cloud — not the hook layer.

## Channels checked

Each row records what was checked, on what date, and what the channel does and does not carry.

<!-- channel inventory continues in the sections below -->
