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
# data_dir: paste the `data_dir=…` line SKILL.md's "Mid-session staleness &
# restart cadence" section carries — it is the ONLY place the real directory is
# resolvable (see the paragraph below). Do not substitute an env var here.
# the commit lane-launcher.sh recorded when this lane last (re)started (#792)
# tr -d '\r': strip a Windows CRLF read hazard on any captured value (the
# repo's standing convention — see the CHANGELOG's #1176/F2 note) before it
# reaches the git log range below.
lane_launch_commit="$(cat "$data_dir/lanes/<lane>-launch-commit" 2>/dev/null | tr -d '\r')"
# merged changes to the claude-ops plugin the running lane has NOT consumed
[[ -n "$lane_launch_commit" ]] && git log --oneline "${lane_launch_commit}..${default}" -- plugins/claude-ops/
```

**`data_dir` comes from SKILL.md, not from the environment.** Per current
[plugins-reference](https://code.claude.com/docs/en/plugins-reference#environment-variables),
`${CLAUDE_PLUGIN_DATA}` is exported as a real environment variable only to hook
processes and MCP/LSP server subprocesses; for a plugin's **skill and agent
content** it instead resolves by inline substitution "anywhere the placeholder
appears". Both facts cut against resolving it here: this reference file is read
raw rather than rendered as skill content (so a placeholder written here would
not substitute), and the probe runs through the Bash tool (so the env var is
unset there). An env-var-with-fallback expression would therefore have silently
resolved to the unqualified `~/.claude/plugins/data/claude-ops` guess, missed
the marketplace-qualified directory Claude Code actually uses, read no marker,
and skipped the staleness check without saying so. SKILL.md — which *is* skill
content — carries the substituted `data_dir=` assignment; take it from there.

`<lane-launch-commit>` (substitute the lane's own name for `<lane>` above) is the
repo HEAD `lane-launcher.sh` captured when `lanes start`/`restart` last (re)started
that lane — written to `<data-dir>/lanes/<lane>-launch-commit` right after the
launch's pre-launch pull, for every lane actually (re)started that run (`start`
leaves the marker untouched for a lane it skipped as already-running; a
(re)start that cannot record its own commit deletes the previous launch's marker
rather than leaving it to be misread as this session's launch point). The lane
name is the marker's filename, so config preflight rejects a lane name that is
not a single path component — the path above is literally true for every
accepted name. An empty `lane_launch_commit` means no marker exists for that
lane (never started/restarted through `lane-launcher.sh` on this machine, or the
last (re)start could not record one) — the probe has nothing to diff against and
is skipped rather than run against a resolved-empty range. Any probe output = an
unconsumed merge. Swap the pathspec for whichever installed plugin a lane runs.

**Not an injection vector today, but treat it as untrusted if that ever changes.**
`lane-launcher.sh` writes `lane_launch_commit` from `git rev-parse HEAD` only — a
bare hex SHA, so reading it back and interpolating it unquoted into `git log
"${lane_launch_commit}..${default}"` above carries no shell-injection risk. If a
future change ever sources this value from something other than `git rev-parse`
(external input, a hand-edited marker file, anything not mechanically
hex-constrained), that value must never be interpolated unquoted into the probe
command — validate it (e.g. `[[ "$lane_launch_commit" =~ ^[0-9a-f]{7,64}$ ]]`)
before it reaches `git log`.

**Not an `!` injection candidate.** This probe is deliberately a body instruction,
not `!` dynamic-context injection — it fails every condition of the precompute
convention (playbooks skill-authoring `reference/precompute-context.md`). It is
**conditional**, consulted only when weighing a restart rather than up front on
every `lanes` invocation; it needs a **computed argument** (`<lane-launch-commit>`,
plus the pathspec of whichever plugin a lane runs) that a single-pass injection
cannot supply; and its `git fetch` is **neither bounded nor pure-read** — a network
round-trip that also updates remote-tracking refs. Safe to run by hand (it touches
no branch or worktree), wrong to inline at load time.

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
