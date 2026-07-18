# session-flow

A Claude Code plugin bundling six skills for one cohesive capability: managing the lifecycle of a
working session — where you are in the work, how to pause and resume it, how to recover it after an
interruption, whether its assumptions are still current, what to learn from it, and how to arm it
for delegation-heavy tasks.

| Skill | Question it answers |
|---|---|
| `/session-flow:workflow` | Where am I in the staged dev workflow, and what comes next? |
| `/session-flow:handoff` | How do I save this session's state so a fresh `/clear` session resumes without rediscovery? |
| `/session-flow:keep-going` | We were interrupted — what was running, what survived, and where does the main task continue? |
| `/session-flow:retro` | What happened this session, what did we learn, and how do we codify it? |
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
crash, a disconnect, or a long gap. Inventories the off-thread work (background tasks, shells,
monitors, scheduled tasks, workflows, subagents — whatever the current harness exposes), inspects
each item's real state from its own artifact rather than assuming it finished or died, resumes the
resumable and restarts the dead, then reconciles the main thread from a fresh read of its backing
plan or handoff file and continues. Safe, idempotent work auto-resumes; re-running anything with
external side effects (a push, a PR comment, a deploy) is gated so a re-fire cannot double-apply.

```shell
/session-flow:keep-going              # inventory → inspect → recover → reconcile → report
```

### retro

Structured session retrospective: extracts transcript metrics via a bundled stdlib-only parser
(multi-session-aware — walks the handoff chain), assesses quality across five dimensions against
the consuming repo's own conventions, checks Claude Code auto-memory for feedback regressions, and
codifies user-approved learnings. Health scores persist across sessions for trend analysis.

```shell
/session-flow:retro            # full 5-phase analysis (default)
/session-flow:retro codify     # persist a specific mid-session learning
/session-flow:retro trends     # cross-session score history
/session-flow:retro quick      # abbreviated, for limited context
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
the working branch's base has drifted; confirms cited skills/plugins still exist under that name
and that installed versions match the repo source; and flags memory-tier entries whose subjects
have since landed. It reports the drift and hands back a re-anchored picture — it does not resume
the work (that is `keep-going`), inventory worktrees (`/source-control:worktree` status), or triage
PR feedback (`/source-control:babysit-prs`).

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
directory (per-project files) — never in the consumer's repo. Handoff save-points are memory-tier
working files in the consumer's project (`.work/handoffs/` by default) — machine-local, never
committed. Network: none — the bundled transcript parser is stdlib-only Python 3.10+ reading local
`~/.claude/projects/` transcripts.
