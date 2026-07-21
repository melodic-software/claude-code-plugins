# Mid-session refresh: why a running lane can't hot-reload its own fix

Loop lanes routinely merge fixes to the very plugins they run on (`babysit` fixes
`babysit`, the work lane fixes `work-items`). The question this file answers
(#514): can a **running** lane consume a just-merged fix to its own skill files
without an operator restart?

## Empirical answer: no true mid-session hot-reload for a running loop lane

Three independently sufficient facts, each verified against current Claude Code
docs, block it — any one alone is decisive:

1. **A running session keeps its launch-time plugin versions.** Merging to the
   marketplace source does nothing to a live session until the local install is
   updated; Claude Code's post-start auto-update runs once (random delay ≤ 10 min)
   and "the running session keeps using the versions it loaded at launch"
   ([discover-plugins](https://code.claude.com/docs/en/discover-plugins)).

2. **`/loop` does not re-read the skill each cycle.** A rendered `SKILL.md` enters
   the conversation once and "stays there for the rest of the session … Claude Code
   does not re-read the skill file on later turns"; an identical re-invocation gets
   an "already loaded" note, not a fresh read from disk
   ([skills — Skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle)).
   So even an updated on-disk copy is never re-injected into the running loop.

3. **A loop can't reload itself.** `/reload-plugins` is a built-in command; a
   scheduled/loop fire delivers built-in commands to Claude "as plain text instead
   of executing" them, so a lane cannot self-trigger a reload mid-run
   ([scheduled-tasks](https://code.claude.com/docs/en/scheduled-tasks)).

`/reload-plugins` *does* pick up on-disk `SKILL.md` edits for an **interactive**
session ([plugins-reference](https://code.claude.com/docs/en/plugins-reference)),
but that path needs a human to type it and does not reach an autonomous loop whose
skill body is already fixed in context.

**Conclusion:** restart is the honest mechanism. It also resets context bloat
(composes with #496's restart discipline), so the live decision is restart
*frequency*, not hot reload.

## Detecting that a self-fix landed (checkable git probe)

Don't restart blindly. A lane is stale for one of its plugins when the repo's
default branch carries commits touching that plugin's path since the lane launched.
Read-only, pure git — resolve the default branch rather than assuming `main`:

```bash
git fetch origin -q
# default branch of this repo — never hardcode main/master
default="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
# merged changes to the claude-ops plugin the running lane has NOT consumed
git log --oneline "<lane-launch-commit>..${default}" -- plugins/claude-ops/
```

`<lane-launch-commit>` is the repo HEAD when `lanes start`/`restart` last ran (the
launch pulls first, so a running lane's skills correspond to that commit). Any
output = an unconsumed merge. Swap the pathspec for whichever installed plugin a
lane runs.

Getting those changes onto disk on restart (marketplace refresh + per-scope
update) is the `plugins` skill's job — see its
[context/sync.md](../../plugins/context/sync.md); the lanes launch already runs
`claude plugin marketplace update`. Not duplicated here.

## Restart cadence

- **Trigger-based:** when the probe shows a merge touching a plugin a lane runs,
  restart that lane at its next cycle boundary — `/claude-ops:lanes restart <lane>`
  re-pulls, refreshes the marketplace, and relaunches from the canonical prompt,
  so the merged skill body loads. Restart discards the lane's in-flight
  conversation, so prefer a cycle boundary over mid-cycle.
- **Periodic floor:** even with no detected merge, restart lanes on the daily
  harvest/reset cadence (the same restart that clears context bloat, #496). This
  bounds self-fix staleness to at most one cadence interval.
- **Until restart:** a behavior known-broken-but-fixed-on-main must be carried as a
  temporary workaround in the loop prompt — the existing prompt rule for *unmerged*
  fixes, extended here to *merged-but-not-yet-reloaded* fixes.
