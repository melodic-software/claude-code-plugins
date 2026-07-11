# session-flow

A Claude Code plugin bundling four skills for one cohesive capability: managing the lifecycle of a
working session — where you are in the work, how to pause and resume it, what to learn from it, and
how to arm it for delegation-heavy tasks.

| Skill | Question it answers |
|---|---|
| `/session-flow:workflow` | Where am I in the staged dev workflow, and what comes next? |
| `/session-flow:handoff` | How do I save this session's state so a fresh `/clear` session resumes without rediscovery? |
| `/session-flow:retro` | What happened this session, what did we learn, and how do we codify it? |
| `/session-flow:orchestration-brief` | How do I arm this session (or a spawned worker) with proactive-orchestration imperatives? |

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
skill always STOPS after emitting the save-point — continuing would defeat the purpose.

```shell
/session-flow:handoff                 # auto-detect full vs prompt-only
/session-flow:handoff prompt          # force prompt-only
/session-flow:handoff file phase-3    # force full handoff, topic "phase-3"
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

### orchestration-brief

Arms the current session for an orchestration-heavy task by loading six proactive-orchestration
imperatives (delegate/fan-out, spec-every-spawn, fresh-context verify, run-workers-well, nested
subagents, surface drift) as standing instructions — or exports them as a paste-ready, tool-agnostic
brief for a spawned worker or fresh session.

```shell
/session-flow:orchestration-brief                # prime this session
/session-flow:orchestration-brief worker         # paste-ready worker brief
/session-flow:orchestration-brief handoff compact # headline-only fresh-session brief
```

## Consumer conventions

The skills adapt to the consuming repo rather than imposing structure:

- **Stage skills** — `workflow` routes to the repo's own stage skills when they exist; every stage
  degrades gracefully to inline execution.
- **Artifact location** — `handoff` and `workflow` honor a repo-documented convention for
  save-points/work journals (declared in the repo's `CLAUDE.md` / rules); the default is
  `.claude/handoffs/` in the project.
- **Quality gates and conventions** — build/test/lint commands, review criteria, and codification
  targets all come from the consuming repo's own instruction files.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install session-flow@melodic-software
```

## Configuration

No `userConfig`. State: retro score history persists under the plugin's `${CLAUDE_PLUGIN_DATA}`
directory (per-project files) — never in the consumer's repo. Handoff save-points are project files
by design (they travel with the repo). Network: none — the bundled transcript parser is
stdlib-only Python 3.10+ reading local `~/.claude/projects/` transcripts.
