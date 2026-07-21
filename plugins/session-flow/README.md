# session-flow

A Claude Code plugin bundling nine skills for one cohesive capability: managing the lifecycle of a
working session — where you are in the work, how to pause and resume it, how to recover it after an
interruption, how to leave it durable before the machine goes away, where things stand and why,
whether its assumptions are still current, what to learn from it while it runs and after, and how to
arm it for delegation-heavy tasks.

| Skill | Question it answers |
|---|---|
| `/session-flow:workflow` | Where am I in the staged dev workflow, and what comes next? |
| `/session-flow:handoff` | How do I save this session's state so a fresh `/clear` session resumes without rediscovery? |
| `/session-flow:keep-going` | We were interrupted — what was running, what survived, and where does the main task continue? |
| `/session-flow:clean-stop` | Before I lose this machine — is everything durable and linked, or is something stranded? |
| `/session-flow:retro` | What happened this session, what did we learn, and how do we codify it? |
| `/session-flow:running-retro` | Mid-flight: how is this session going, what is drifting, and what should change before it costs more? |
| `/session-flow:orient` | Where do we stand, what are we doing, and why — from the durable + off-thread state, not just the conversation? |
| `/session-flow:orchestrate` | How do I arm this session (or a spawned worker) with proactive-orchestration imperatives? |
| `/session-flow:reanchor` | Are this session's assumptions still true, or has reality moved under them? |

## What each skill does

### workflow

The map for a staged development workflow (contract → explore → research → plan → implement → test
→ review → verify → retro). Detects the current position from conversation evidence, suggests the
next stage, and serves ordered checklists for the pre-PR sequence and end-of-session wrap-up. When
the consuming repo defines its own stage skills, it routes to them; otherwise stages execute
inline.

```shell
/session-flow:workflow            # position + next-stage suggestion
/session-flow:workflow steps      # full stage definitions
/session-flow:workflow pre-pr     # ordered pre-PR gate checklist
/session-flow:workflow wrap-up    # end-of-session checklist
/session-flow:workflow spec-first # stage-by-stage execution with /clear between stages
```

### handoff

Writes a mid-session save-point for the `/clear`-and-resume pattern: a durable handoff file (task,
progress, decisions, files modified, tried-and-ruled-out, next steps, TaskList snapshot) plus a
copy-paste resume prompt — or prompt-only when follow-ups are small. Handoff files chain via
`session_id` / `previous_handoff` frontmatter so `retro` can analyze the whole session chain. The
skill always STOPS after emitting the save-point — continuing would defeat the purpose. With
`--bg` it additionally launches a fresh background agent seeded with the resume prompt (via
`claude --bg`, managed with `claude agents`), so the work resumes without a manual
`/clear`-and-paste.

```shell
/session-flow:handoff                 # auto-detect full vs prompt-only
/session-flow:handoff prompt          # force prompt-only
/session-flow:handoff file phase-3    # force full handoff, topic "phase-3"
/session-flow:handoff --bg            # hand the resume prompt to a background agent
```

### keep-going

The resume counterpart to `handoff`: recovers a session after any interruption — a rate limit, a
crash, a disconnect, or a long gap — and, mid-session, verifies off-thread work that *looks* stalled
when you ask it to ("check the monitor", "poke it", "is it stuck"). Inventories the off-thread work
(background tasks, shells, monitors, scheduled tasks, workflows, subagents — whatever the current
harness exposes), inspects each item's real output rather than assuming it finished or died, and
acts on evidence: work that is progressing (even slowly) is left alive, the resumable is resumed,
the provably-dead is restarted, then it reconciles the main thread from a fresh read of its backing
plan or handoff file and continues. Progress-vs-elapsed only raises suspicion — it never authorizes
a kill on a hunch. Safe, idempotent work auto-resumes; re-running side-effectful work (a push, a PR
comment, a deploy) *and* killing or restarting work it cannot prove is dead are gated. After a usage
limit lifts it continues rather than summarizing-and-stalling (the block is already over if it is
running again); while a limit still holds it hands back via `handoff` rather than self-arming a
scheduler. Intent is inferred from the conversation; arguments are optional.

```shell
/session-flow:keep-going              # inventory → inspect → recover → reconcile → report
```

### clean-stop

The go/stop mirror of `keep-going`: instead of recovering after an
interruption, it makes the interruption safe beforehand. Sweeps every repo and
worktree the session touched, inspects real state, and closes the gaps —
pushes unpushed or coherently committable work durable, ensures every pushed
non-default branch has a PR, files follow-ups as issues linked to that PR, and puts the
resume context in the PR and issue bodies so a cold agent could pick it up.
Ambiguous work-in-progress and stashes are surfaced rather than force-committed
or dropped; destructive cleanup (deleting branches, removing worktrees) runs
only on provably-safe state. Closes on a binary verdict: free-and-clear, or a
named list of dangling items. It supersedes a local `handoff` when the machine
itself may go away — breadcrumbs on the remote survive the disk. PR, issue, and
worktree mechanics route to whatever capabilities are installed, falling back
to direct `git` / `gh`.

```shell
/session-flow:clean-stop              # inspect → make durable → link → prune-safe → verdict
```

### retro

Structured end-of-session retrospective: extracts transcript metrics via a bundled stdlib-only
parser (multi-session-aware — walks the handoff chain), assesses quality across five dimensions
against the consuming repo's own conventions, checks Claude Code auto-memory for feedback
regressions, and codifies user-approved learnings. Health scores persist across sessions for trend
analysis.

```shell
/session-flow:retro            # full 5-phase analysis (default)
/session-flow:retro codify     # persist a specific mid-session learning
/session-flow:retro trends     # cross-session score history
/session-flow:retro quick      # abbreviated, for limited context
```

### running-retro

The live counterpart to `retro`: an in-flight retrospective checkpoint taken *while the work is
still going*, rather than after. Zero-arm — nothing to set up in advance, because the on-disk
transcript is lossless across compaction (the same record `retro`'s parser reads). The main agent
adds a 2-3 line subjective-state note (the one signal disk cannot hold), then delegates the analysis
to a fresh subagent that runs `retro`'s parser, selectively reads the flagged transcript spans, and
classifies each finding by category and suggested resolution route (CLAUDE.md fix / rule fix / skill
change / new-skill candidate / tracker issue). Findings append to a cumulative running ledger — one
stable file per session chain, memory-tier, never committed (`.work/running-retros/` by default via
`reference/topic-docs.md`). It captures and routes only: codification stays with `retro codify`,
tracker filing is offered not automatic, the session is never scored, and it is non-terminating
(unlike `handoff`, it does not `/clear`). Composes with `/loop` for periodic checkpoints.

```shell
/session-flow:running-retro            # checkpoint: note → delegate → classify → append → offer routes
/session-flow:running-retro phase-3    # same, naming the ledger topic slug
```

### orient

A read-only orientation briefing: *where do we stand, what are we doing, and why.* Unlike the
built-in `/recap` (which summarizes the conversation only and auto-fires on an idle terminal),
`orient` also reads the durable, off-thread state a conversation does not hold — handoff
save-points, the workflow checklist, running-retro ledgers (resolved through
`reference/topic-docs.md`), plus git state, open PRs, and open work-items — and synthesizes a
goal/why, where-we-stand, decisions-made, and direction briefing. A skill cannot invoke the built-in
`/recap`, so it synthesizes the conversation summary inline and adds the durable layer on top. It is
strictly read-only: it writes nothing and routes rather than acts — freshness verification to
`reanchor`, off-thread recovery to `keep-going`, next-stage to `workflow`, learnings to `retro`.

```shell
/session-flow:orient              # read-only briefing: goal/why → where-we-stand → decisions → direction
```

### orchestrate

Arms the current session for an orchestration-heavy task by loading seven proactive-orchestration
imperatives (delegate/fan-out, spec-every-spawn, fresh-context verify, run-workers-well, nested
subagents, surface drift, calibrate-to-conditions) as standing instructions — or exports them as a
paste-ready, tool-agnostic brief for a spawned worker or fresh session.

```shell
/session-flow:orchestrate                # prime this session
/session-flow:orchestrate worker         # paste-ready worker brief
/session-flow:orchestrate handoff compact # headline-only fresh-session brief
```

### reanchor

Verifies a session's working assumptions against live reality before it builds on them — the
premise-freshness counterpart to `keep-going`'s recovery. For the PRs, issues, and branches a
handoff or locked plan references, it confirms each is still in the claimed state; checks whether
the working branch is now behind its base; confirms cited skills/plugins still exist under that
name and that installed versions match the repo source; and flags memory-tier entries whose
subjects have since landed. It reports the drift and hands back a re-anchored picture — it does not
resume the work (that is `keep-going`), enumerate worktrees, or triage PR feedback. When
`source-control` is installed it cites that plugin's `worktree` status for the cross-worktree
inventory and leaves PR-feedback triage to `babysit-prs`; otherwise it does the reduced local
checks and reports the fuller inventory as unavailable.

```shell
/session-flow:reanchor            # verify session premises → report drift → re-anchored picture
```

## Consumer conventions

The skills adapt to the consuming repo rather than imposing structure:

- **Stage skills** — `workflow` routes to the repo's own stage skills when they exist; every stage
  degrades gracefully to inline execution.
- **Artifact location** — `handoff` and `workflow` honor a repo-documented convention for
  save-points/work journals (the `.claude/topic-docs.yaml` concern file, or the repo's `CLAUDE.md`
  / rules); the defaults are `.work/handoffs/` for handoff save-points and
  `.work/<slug>/workflow-checklist.md` for the per-topic workflow checklist — memory tier per the
  marketplace topic-docs convention, self-ignoring and never committed
  (`reference/topic-docs.md`).
- **Quality gates and conventions** — build/test/lint commands, review criteria, and codification
  targets all come from the consuming repo's own instruction files.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install session-flow@melodic-software
```

## Configuration

No `userConfig`. State: retro score history persists under the plugin's `${CLAUDE_PLUGIN_DATA}`
directory (per-project files) — never in the consumer's repo. Handoff save-points
(`.work/handoffs/` by default) and running-retro ledgers (`.work/running-retros/` by default) are
memory-tier working files in the consumer's project — machine-local, never committed. Network: three
skills reach the network. `reanchor` queries live host state via `git`/`gh`
to verify a session's referenced PRs/issues/branches and installed-vs-repo plugin versions, and
degrades to reporting what it could not verify when that authenticated egress is unavailable.
`clean-stop` pushes unpushed commits and creates or updates PRs and issues over the network via
`git push` and `gh` — routing through whatever pull-request / work-item capabilities are installed
and falling back to direct `git`/`gh` — to make session work durable on the remote. `orient`
optionally runs `gh pr list` (read-only) to include open pull requests in its briefing and, when a
work-item tracker capability is installed, reads its open items (which may reach a remote tracker) —
degrading to local git state alone when `gh` or the tracker is absent or unauthenticated. The other six
skills — workflow, handoff, keep-going, retro, running-retro, and orchestrate — are network-free
(both retro and running-retro use the same stdlib-only Python 3.10+ parser reading local
`~/.claude/projects/` transcripts).
