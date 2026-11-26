# session-flow

A Claude Code plugin with twenty skills for managing the lifecycle of a working session. The
skills answer where you are in the work, how to pause and resume it, how
to recover it after an interruption, how to leave it durable before the machine goes away, how to
retire finished work and reconcile the task ledger, where things stand and why, whether the
session's assumptions are still current, what to learn from it while it runs and after, where your
sessions lose time and tokens over weeks, where permissions and asks get in the way, and how to arm
it for delegation-heavy tasks.

| Skill | Question it answers |
|---|---|
| `/session-flow:workflow` | Where am I in the staged dev workflow, and what comes next? |
| `/session-flow:handoff` | How do I save this session's state so a fresh `/clear` session resumes without rediscovery? |
| `/session-flow:continue-in-background` | I'm stepping away. How does a background agent pick this up and keep it moving now? |
| `/session-flow:keep-going` | We were interrupted. What was running, what survived, and where does the main task continue? |
| `/session-flow:find-handoff` | I wrote a handoff, ran `/clear`, and lost the resume prompt. Where is it and how do I resume? |
| `/session-flow:clean-stop` | Before I lose this machine, is everything durable and linked, or is something stranded? |
| `/session-flow:retro` | What happened this session, what did we learn, and how do we codify it? |
| `/session-flow:audit-sessions` | Across every session on this machine, which ones lost the most time or tokens, and what would fix it? |
| `/session-flow:audit-friction` | Where do permission prompts, auto-mode denials, hook blocks and the agent's own asks get in my way, and what should change? |
| `/session-flow:running-retro` | Mid-flight: how is this session going, what is drifting, and what should change before it costs more? |
| `/session-flow:orient` | Where do we stand, what are we doing, and why, from the durable + off-thread state, not just the conversation? |
| `/session-flow:recall` | What have past sessions already tried on this topic, and what was kept or reverted? |
| `/session-flow:orchestrate` | How do I arm this session (or a spawned worker) with proactive-orchestration imperatives? |
| `/session-flow:reanchor` | Are this session's assumptions still true, or has reality moved under them? |
| `/session-flow:reconcile` | Is anything still running that should be retired, and does the task ledger match reality? |
| `/session-flow:setup` | Are the observer's runtime prerequisites and configuration right on this machine? |
| `/session-flow:recommend-skills` | Which skills fit this moment, and what am I forgetting I could run? |
| `/session-flow:tidy-work` | What is piling up in `.work`, what is still in flight, and what is safe to remove? |
| `/session-flow:step-away` | I'm going away for a while. How does this session keep working, refuse every prompt, and show me what it refused when I'm back? |
| `/session-flow:go-with-recommendations` | I'm back. Are the latest recommendations still right, and can you carry them out? |

## Contents

- [Output styles](#output-styles)
- [What each skill does](#what-each-skill-does)
  - [workflow](#workflow)
  - [handoff](#handoff)
  - [continue-in-background](#continue-in-background)
  - [keep-going](#keep-going)
  - [find-handoff](#find-handoff)
  - [clean-stop](#clean-stop)
  - [retro](#retro)
  - [audit-sessions](#audit-sessions)
  - [audit-friction](#audit-friction)
  - [running-retro](#running-retro)
  - [orient](#orient)
  - [recall](#recall)
  - [orchestrate](#orchestrate)
  - [reanchor](#reanchor)
  - [reconcile](#reconcile)
  - [recommend-skills](#recommend-skills)
  - [step-away](#step-away)
  - [go-with-recommendations](#go-with-recommendations)
  - [setup](#setup)
- [Consumer conventions](#consumer-conventions)
- [Install](#install)
- [Requirements](#requirements)
- [Configuration](#configuration)
  - [Options reference](#options-reference)
  - [How to set these](#how-to-set-these)
  - [Upstream documentation](#upstream-documentation)

## Output styles

- **`Brain Fried`**. Opt-in simplified register for cognitively depleted sessions (short words,
  short answers, two options max). Select it in `/config` → **Output style**. Coexists with
  `/education:explain` for one-shot deep explanations (#1223).

## What each skill does

### workflow

The map for a staged development workflow (interview, calling [explore], [research] and [PRD] as
detours → design → plan → [decompose] → implement → test → review → verify → ship → retro). Detects the current position from conversation evidence, suggests the
next stage, and serves ordered checklists for the pre-PR sequence and end-of-session wrap-up. When
the consuming repo defines its own stage skills, it routes to them; otherwise stages execute
inline.

```shell
/session-flow:workflow            # position + next-stage suggestion
/session-flow:workflow steps      # full stage definitions
/session-flow:workflow pre-pr     # ordered pre-PR gate checklist
/session-flow:workflow wrap-up    # end-of-session checklist
/session-flow:workflow spec-first # stage-by-stage execution from a written spec
```

### handoff

Writes a mid-session save-point for the `/clear`-and-resume pattern: a durable handoff file, whose
body sections `reference/structure.md` defines, plus a copy-paste resume prompt, or prompt-only
when follow-ups are small. Handoff files chain via `session_id` / `previous_handoff` frontmatter so
`retro` can analyze the whole session chain. The
skill always STOPS after emitting the save-point. Continuing would defeat the purpose. The
save-point machinery itself (destination resolution, path choice, redaction, rails prompt) lives in
the shared `reference/save-point.md` engine doc that `continue-in-background` also delivers from.

The handoff is **shape 3** (`handoff_shape: 3`): a small handoff file per hop that a resume reads,
plus one archive file per hop under `.work/handoffs/<archive>` holding, verbatim, what that hop
moved out of the handoff file. The handoff file carries the user's verbatim goal, intent and vision, the
current rules with stable `[R<n>]` ids, a one-line-per-change direction trail, the remaining
work, the last Prior-sessions rows, and, as its final section, the resume prompt itself; its
frontmatter names the chain root, the hop and the archive directory. A stdlib-only Python
script, `scripts/save_point.py`, writes every deterministic field and the archive file (`new`),
replaces the reasoning slots from one JSON object in a single write (`fill`), validates the
finished file, its size cap and its carry from the predecessor before the rails are shown
(`validate`, exit 0 gates the prompt), and prints the stored prompt (`emit`) so the on-screen
rails and the file are the same bytes. The model supplies only the reasoning slot values. The
resume prompt tells the next session to invoke this skill for its own save-point rather than
writing a handoff file free-hand. Shape-2 files (one self-contained file per hop carrying the
whole chain) and older shape-1 files are read as before and never rewritten; a shape-2 chain's
next hop writes shape 3. Update session-flow before resuming a shape-3 chain: an older
`save_point.py` refuses to validate or build on one.

The response opens with a **"You are here" position panel** for the operator, a vertical rail with
one line per unit of whatever the work is divided into (workflow stages, plan phases, a sub-issue
chain, tasks, or completion criteria), the current position marked, a completeness read, and three
one-line blocks: what was done this session, where we are, what is next. It restates what the
save-point already established rather than sweeping durable state; that is `orient`, and it never
delays or displaces the rails prompt. Work with no delineated units gets the prose blocks and no
rail; units are never invented to fill one.

With the `wip_commit` option on, a handoff you start to pause the work first makes one local
`chore(wip):` commit of the tracked files the work changed, never pushed; see "Option details".

```shell
/session-flow:handoff                 # auto-detect full vs prompt-only
/session-flow:handoff prompt          # force prompt-only
/session-flow:handoff file phase-3    # force full handoff, topic "phase-3"
```

### continue-in-background

The delegation counterpart to `handoff`: same save-point engine, different delivery. Instead of
handing the user a `/clear`-then-paste prompt for later, it launches a fresh detached background
agent seeded with the rails resume prompt (via `claude --bg`, managed with `claude agents`), so the
task keeps moving while the user is away. It launches only on the user's explicit request, never
self-elected, and gates the launch on a clean tree (save-point files exempt): other uncommitted
changes would not carry into the isolated worktree the background session edits in, so it falls
back to the manual `/clear`-then-paste exit and says why. The launched agent is a NEW session: it
inherits neither the current session's CLI flags nor its model/effort choices (for what a new
session starts on, see
[model config: a new session starts on a different model](https://code.claude.com/docs/en/model-config#a-new-session-starts-on-a-different-model-than-you-picked)),
the skill mirrors and reports the flags the resumed work depends on. Like `handoff`, it STOPS after delivery. The
background agent is the continuation, and nothing is monitored or babysat.

```shell
/session-flow:continue-in-background              # save-point, launch, report, stop
/session-flow:continue-in-background file phase-3 # force full save-point, topic "phase-3"
```

### keep-going

The resume counterpart to `handoff`: recovers a session after any interruption, a rate limit, a
crash, a disconnect, or a long gap, and, mid-session, verifies off-thread work that *looks* stalled
when you ask it to ("check the monitor", "poke it", "is it stuck"). Inventories the off-thread work
(background tasks, shells, monitors, scheduled tasks, workflows, subagents, whatever the current
harness exposes), inspects each item's real output rather than assuming it finished or died, and
acts on evidence: work that is progressing (even slowly) is left alive, the resumable is resumed,
the provably-dead is restarted, then it reconciles the main thread from a fresh read of its backing
plan or handoff file and continues. Progress-vs-elapsed only raises suspicion. It never authorizes
a kill on a hunch. Safe, idempotent work auto-resumes; re-running side-effectful work (a push, a PR
comment, a deploy) *and* killing or restarting work it cannot prove is dead are gated. After a usage
limit lifts it continues rather than summarizing-and-stalling (the block is already over if it is
running again); while a limit still holds it hands back via `handoff` rather than self-arming a
scheduler. Intent is inferred from the conversation; arguments are optional. Three situations get
their own handling, listed in the order keep-going reaches them:

| Situation | What keep-going does | For example |
|---|---|---|
| The session that started the work has ended, so the agent and task ids it handed out no longer resolve | Looks the work up by what outlives a session: its branch, PR, worktree or commits | A `continue-in-background` session closed with the laptop; keep-going reads its pushed branch and draft PR |
| Another agent's trail, such as a `handoff` save-point, reports progress | Checks each status claim on the artifact it names, gives the trail exactly one verdict (ratify, ship the finished recommendation, continue, restart), and reports what it took over apart from what it redid | A save-point says the fix is pushed; keep-going opens the branch before anything rests on that |
| An item fails again after a retry | Fits each retry to the cause of the failure before it, and reruns unchanged only when that cause lay outside the work or none shows. When the second retry fails too, it marks the item abandoned and redraws the plan for what is left so nothing waits on it | A background test run hit its time limit, and both retries, each on a narrower slice, hit it again |

```shell
/session-flow:keep-going              # inventory → inspect → goal-align → recover → reconcile → report
```

### find-handoff

The recovery counterpart to `handoff`: finds a save-point whose resume prompt was written but never
copied. The operator ran `/clear` before copying it, leaving the fresh session with zero context
and no path to the handoff on disk. Runs a read-only detection ladder: known-location glob of the
current repo's `<memory_dir>/handoffs/`, then a bounded, recency-ranked scan of transcripts in the
project directories the `transcript_scope` option allows (this worktree first by default, asking
before any other project; see "Option details") (excluding the current session's own file, since `/clear` opens a new transcript in the same project
dir and the pre-clear content is a sibling) for the handoff directive and dashed-rail markers, which
`reference/save-point.md` documents as a stable detection contract, then a confirm-before-resume
gate. Handles both output modes (file-based and prompt-only, which writes no file). A shape-2 or
shape-3 handoff file stores its own resume prompt as its final section, so the known-location
rung hands
it back from the file alone via `scripts/save_point.py emit`, no transcript needed; an unfinished
skeleton (one still carrying fill slots) is named and skipped, never presented as the lost
handoff. Read-only and redaction-aware: surfaces only the resume prompt and handoff metadata, never
raw transcript content. Routes to `keep-going` when the recovered session ended mid-work rather
than at a clean save-point.

```shell
/session-flow:find-handoff            # locate → confirm → resume, or hand to keep-going
```

### clean-stop

The go/stop mirror of `keep-going`: instead of recovering after an
interruption, it makes the interruption safe beforehand. Sweeps every repo and
worktree the session touched, inspects real state, and closes the gaps,
pushes unpushed or coherently committable work durable, ensures every pushed
non-default branch has a PR, files follow-ups as issues linked to that PR, and puts the
resume context in the PR and issue bodies so a cold agent could pick it up.
Ambiguous work-in-progress and stashes are surfaced rather than force-committed
or dropped; destructive cleanup (deleting branches, removing worktrees) runs
only on provably-safe state. Closes on a binary verdict: free-and-clear, or a
named list of dangling items. It supersedes a local `handoff` when the machine
itself may go away. The PR and issue bodies live on the remote, so they survive a lost disk. PR, issue, and
worktree mechanics route to whatever capabilities are installed, falling back
to direct `git` / `gh`.

```shell
/session-flow:clean-stop              # inspect → make durable → link → prune-safe → verdict
```

### retro

Structured end-of-session retrospective: extracts transcript metrics via a bundled stdlib-only
parser (multi-session-aware: it walks the handoff chain), assesses quality across five dimensions
against the consuming repo's own conventions, checks Claude Code auto-memory for feedback
regressions, and codifies user-approved learnings. Health scores persist across sessions, and
`/session-flow:audit-sessions trends` analyzes them. With the `retro_lenses` option at `3`, the analysis runs as three parallel review
passes merged before scoring. The `ci-runs` target runs the same analysis over chosen CI lane runs,
read locally from their sealed transcripts in a lane transcript sink (the
[lane-transcripts contract](../../docs/contracts/lane-transcripts/README.md)), and keeps a score
history per lane.

```shell
/session-flow:retro            # full 5-phase analysis (default)
/session-flow:retro quick      # abbreviated, for limited context
/session-flow:retro ci-runs --lane pr-verify --last 3 --sink /path/to/sink
```

Token totals count each assistant message once and human messages count only typed turns, so
numbers from 0.46.0 on are lower than earlier retros' for the same kind of session (#5818).

One recurring mistake, or the lessons in recent merged PRs' review comments, go to
`/corrections:codify` (its `reviews` action), not to a retro mode.

### audit-sessions

Cross-session audit: a stdlib collector reads every transcript under `~/.claude/projects` into a
durable local store (one redacted record per session, incremental, retention-bounded), and a sweep
reports per-session metrics against a shipped reference baseline, shows this store's p90 beside
each threshold and marks a stale baseline, flags transcript-format drift
between Claude Code versions, and routes each finding to the skill that would act on it. It never
applies a finding. `/corrections:codify preferences` reads the stored excerpts of your own typed
turns through the `excerpts-only` consumer mode, for a line in a user-scope file, never a repository
file. The `correction` action has the session's model judge
which stored short turns corrected the agent and reports them in a separate, unranked `Judged`
section beside the measured findings. The `trends` action reads the health scores `retro` records
and shows how they move across sessions, with delivery metrics beside them when the work-items
plugin is installed. The `pr` action looks back over one pull request: it finds the sessions that
linked it or ran on its head branch in its repository, subagents included, reads them in subagents
sized to the transcripts, and hands the PR's review comments to `/corrections:codify reviews --pr`
when that plugin is installed, which proposes checks only for a PR in the current checkout's
repository.

```shell
/session-flow:audit-sessions                                # collect, then sweep every session
/session-flow:audit-sessions pr --number 123 --repo 'o/r'   # every session behind one pull request
/session-flow:audit-sessions sweep --since 2026-09-01       # a date window
/session-flow:audit-sessions --scope project --write-report # this repository, saved report
/session-flow:audit-sessions correction --since 2026-09-01  # model-judged corrections, reported unranked
/session-flow:audit-sessions trends                         # cross-session score history and delivery metrics
```

### audit-friction

Permission and autonomy friction across this machine's sessions. The audit-sessions collector
records each denial (classifier category, hook, rule), approved prompt, ask, hand-off and
correction per session; a script mines a window of them, maps each to the permission rules that
could match it, and diffs a later window against a saved baseline. Agents classify the friction,
plan the fixes and verify the claims at a depth you pick. The run ends in one decision brief, with
scripts you run for the edits auto mode blocks; it changes no setting itself.

```shell
/session-flow:audit-friction                         # last 7 days, every project
/session-flow:audit-friction --days 14 --verify full # wider window, check every claim
/session-flow:audit-friction remeasure               # compare with the saved baseline
```

### running-retro

The live counterpart to `retro`: an in-flight retrospective checkpoint taken *while the work is
still going*, rather than after. Zero-arm: nothing to set up in advance, because the on-disk
transcript is lossless across compaction (the same record `retro`'s parser reads). The main agent
adds a 2-3 line subjective-state note (the one signal disk cannot hold), then delegates the analysis
to a fresh subagent that runs `retro`'s parser, selectively reads the flagged transcript spans, and
classifies each finding by category and suggested resolution route (CLAUDE.md fix / rule fix / skill
change / new-skill candidate / tracker issue). Findings append to a cumulative running ledger, one
stable file per session chain, memory-tier, never committed (`.work/running-retros/` by default).
It captures and routes only: codification stays with `retro` and `/corrections:codify`,
tracker filing is offered not automatic, the session is never scored, and it is non-terminating
(unlike `handoff`, it does not `/clear`). Composes with `/loop` for periodic checkpoints.

```shell
/session-flow:running-retro            # checkpoint: note → delegate → classify → append → offer routes
/session-flow:running-retro phase-3    # same, naming the ledger topic slug
```

**Session observer.** With `observer_enabled` on, session-flow watches each session without being
asked. Its hooks module runs a live check every `observer_step_every` model steps (default 6) of a long turn (and, when
`observer_turn_end_check` is on, at the end of each tool-using turn): a no-tools fork of the main
conversation that reports at most one process fault tied to a written rule or owner decision. A
finding goes to this session's running-retro ledger and to one row above the prompt, where `1` sends
it to Claude, `2` notes it, `3` disputes it and `0` dismisses it. At each session start a SessionStart
hook analyzes, with a headless `claude -p`, up to two ended sessions that got no live checks, such as
headless lanes. The module needs Claude Code 2.1.331 or later and was tested with `claude plugin test`
on 2.1.331; it runs no checks in `-p` sessions.
Mechanism, cost and config: `reference/observer.md`; prerequisites: `/session-flow:setup`.

### orient

A read-only orientation briefing: *where do we stand, what are we doing, and why.* Unlike the
built-in `/recap` (which summarizes the conversation only and auto-fires on an idle terminal),
`orient` also reads the durable, off-thread state a conversation does not hold: handoff
save-points, the workflow checklist, running-retro ledgers, plus git state, open PRs, and open work-items, and synthesizes a
goal/why, where-we-stand, decisions-made, and direction briefing. A skill cannot invoke the built-in
`/recap`, so it synthesizes the conversation summary inline and adds the durable layer on top. It is
strictly read-only: it writes nothing and routes rather than acts. Freshness verification to
`reanchor`, off-thread recovery to `keep-going`, next-stage to `workflow`, learnings to `retro`.

```shell
/session-flow:orient              # read-only briefing: goal/why → where-we-stand → decisions → direction
```

### recall

Topic history: what past sessions tried on one topic, and how each attempt ended. It lists the
transcript directories `transcript_scope` allows through `scripts/transcript_dirs.sh` (this
worktree first, then the repository's other worktrees, asking before any other project), scans
them with `skills/recall/scripts/recall_scan.py`, which matches literal terms and redacts every
snippet before printing it, and has subagents condense each matching session from those redacted
lines. It adds reverted commits from git, closed unmerged pull requests through `gh`, open and
closed tracker items when `/work-items:track` is available, and postmortems from the
`recall_doc_paths` pathspecs, then reports Tried, Kept, Dropped or reverted, Still reported, and
Still open in chat, opening with the scope it searched. Still reported lists items of a
`recall_report_kinds` kind that were closed and reopened (read from the tracker's state history
with `/work-items:track view --history`, up to ten items), whose fix was reverted, or that repeat a
symptom, plus the topic's postmortems. It writes nothing.

```shell
/session-flow:recall webhook retry budget   # scope line, then tried / kept / reverted / still reported / open
```

### orchestrate

Arms the current session for an orchestration-heavy task by loading seven proactive-orchestration
imperatives (delegate/fan-out, spec-every-spawn, fresh-context verify, run-workers-well, nested
subagents, surface drift, calibrate-to-conditions) as standing instructions, or exports them as a
paste-ready, tool-agnostic brief for a spawned worker or fresh session.

```shell
/session-flow:orchestrate                # prime this session
/session-flow:orchestrate worker         # paste-ready worker brief
/session-flow:orchestrate handoff compact # headline-only fresh-session brief
```

### reanchor

Verifies a session's working assumptions against live reality before it builds on them, the
premise-freshness counterpart to `keep-going`'s recovery. For the PRs, issues, and branches a
handoff or locked plan references, it confirms each is still in the claimed state; checks whether
the working branch is now behind its base; confirms cited skills/plugins still exist under that
name and that installed versions match the repo source; and flags memory-tier entries whose
subjects have since landed. It reports the drift and hands back a re-anchored picture. It does not
resume the work (that is `keep-going`), enumerate worktrees, or triage PR feedback. When
`source-control` is installed it cites that plugin's `worktree` status for the cross-worktree
inventory and leaves PR-feedback triage to `babysit-prs`; otherwise it does the reduced local
checks and reports the fuller inventory as unavailable.

```shell
/session-flow:reanchor            # verify session premises → report drift → re-anchored picture
```

### reconcile

The prune-and-reconcile counterpart to `keep-going`'s resume: where keep-going asks "is it stuck,
pick it back up", reconcile asks "is anything still running that should be retired, and does
the task ledger match reality?" It inventories the off-thread work this session spawned (background
tasks, shells, monitors, scheduled jobs, subagents, the open-ended kinds in
`reference/off-thread-work.md`, the same inventory-and-inspect engine `keep-going` and `orient`
share), inspects each item's real state, retires the ones genuinely finished by clearing them from
tracking, and closes this session's task-ledger items whose work is proven complete. It also reports
the read-only liveness of sibling sessions in the same project, from transcript mtime plus a coarse
tail read, never a deep parse of the unstable JSONL. Auto-settles the provably-finished (closing a
task is evidence-gated, the mirror of never killing work you cannot prove is dead); GATES any kill
of still-running work. It fixes this session only: sibling sessions are visible but report-only, and
a spawned subagent's internal task list is not readable. It touches no git state (that is
`clean-stop`) and does not resume the work (that is `keep-going`).

```shell
/session-flow:reconcile   # inventory → inspect → retire finished + close done → report
```

### recommend-skills

Lets the operator consult the installed catalog instead of remembering it. Renders five buckets: **Now**, **Next**, **Skipped upstream** (artifact-grounded), **Later** (the
in-domain remainder beyond the near horizon, rendered as bare names only), and a rotating
**Spotlight** of three, each as a ranked shortlist of at most five in full treatment plus the
complete remainder by bare name with an explicit count, so nothing is off-screen unstated.

Its contract is two rules: **never omit a candidate's name**, and **never invent one**. A skill the
evidence says already ran is ranked normally and annotated `(ran this session)`, the model's judgment
reaches rank and annotations, never presence. Candidates resolve from a frontmatter index of every
skill, enabled, disabled and not installed (`/harness-ops:inventory --skills-index` when enabled,
else a project-supplied catalog, else the in-context listing *with its truncation disclosed*).
The in-context listing comes last because it omits every manual-only skill and drops descriptions
starting with the least-invoked ones, the very skills worth surfacing. The skill shortlists from
the index, reads only the shortlisted SKILL.md files, asks at most one question, and never enables
or installs a skill. The
`recommend_skills_exclude` option drops disabled or not-installed skills; by default it keeps them,
annotated. Durable state is the primary signal; it builds no probe of its own and routes to
`orient` for that.

Distinct from `workflow`, which routes to exactly one next **stage**: this one lays out the menu and
lets the human choose. Writes only its small Spotlight rotation ledger; otherwise read-only.

```shell
/session-flow:recommend-skills            # menu for the current moment
/session-flow:recommend-skills my-topic   # scope the artifact-grounded reads to a topic slice
```

### step-away

Arms the session to keep working while you are away. Anything that would prompt is refused and
listed in a return report with an id; auto mode denials, blocking questions and MCP server
questions are listed too, and nothing is approved until you are back. Forks, permission or
trust-boundary changes, billable actions and unplanned settings changes are parked in the report
with options and a recommendation while independent work continues. A critical security issue or
an exposed secret stops the affected work and leads the report. The report exists from launch,
is refreshed after each finished piece of work, and lists every external action and every stray
file written in the watched folders. A message that reads as you being back (never a subagent
report, a scheduled prompt or another session's message) shows the report once and marks it
delivered, which removes the absence's state and keeps the report. Bare, started inside the night window, the report is due at the next report-by time;
started outside it, the absence lasts until you return. Launch words override the settings, and an unclear absence
is asked about at launch. Launch warns when the context is heavy or auto mode is off, and
proposes a `/goal` line; the Stop hook holds the same condition without one. Asked for a fresh
session, it launches a background session and arms it from this one before you leave. Opt-in
only: the plugin's PermissionRequest, Elicitation, Stop and UserPromptSubmit hooks run in every
session but do nothing until an absence is started, and exit before Python starts while none
exists. With `away_orchestrate` on, or launch words that ask for it, the run works as an
orchestrator: it delegates and keeps only briefs, verdicts and state in its own context, so it
lasts through compaction. The settings are the six `away_*` options in "Options reference";
`/session-flow:setup` reports each and checks that every watched folder exists.

```shell
/session-flow:step-away                           # start now; the night window sets the report-by time
/session-flow:step-away until 2026-11-20T09:00    # absence with a named report-by time
```

### go-with-recommendations

The return counterpart to `step-away`. Accepts the recommendations in the agent's latest message,
plus any exceptions you state in plain words, after a full evidence check (through
`/discipline:do-your-research full` when that plugin is on, otherwise an inline audit of the
pending recommendations). A recommendation that changed or cannot be confirmed comes back with
the old value, the new value and why, instead of being carried out. During an absence it accepts
recommendations parked in the report, never a refused action, which waits for your return. A bare
accept never approves a refused action, a permission change or an action that could cost money;
name such an item as an exception to approve it.

```shell
/session-flow:go-with-recommendations                       # accept the latest recommendations
/session-flow:go-with-recommendations except the migration  # accept all but the one named
```

### tidy-work

Inventories the gitignored `.work` memory tiers (the repo's memory root, resolved from the concern
file's `memory_dir`, and `~/.work`) that no other skill prunes. `report` (default, read-only) lists
each first-level item with age, size, kind, and whether it is in flight. `normalize` moves misplaced
handoffs and running-retro ledgers into their standard directories. `clean` removes a stale item of
a known kind only when it names at least one issue or PR and every one is closed or merged. A
top-level entry whose name carries one issue or PR number (`lint-5371.log`, `measure-4608`; a year
such as `2026` needs a `pr`, `issue`, or `gh` prefix) is scratch: `report` shows that issue or PR
and its state, and `clean` removes it only once that issue is closed or that PR is merged. Both
actions are dry runs that list exact paths and ask one confirmation before `--apply`, and neither
modifies anything git tracks. Unattributed items are always kept: unknown items (a name with no
number or several, or a tool's own folder), handoffs and running retros whose text names no issue
or PR, every slice and checklist, and the entries of other skills' concern dirs (`reviews/`,
`exports/`). So are in-flight items (a slice whose `INDEX.md` status is not `done`, a recent change,
a clone or worktree inside it, a handoff or scratch entry naming an open issue or PR).
Opt-in only: nothing runs unless invoked.

```shell
/session-flow:tidy-work                  # report
/session-flow:tidy-work clean --days 30  # dry run, then one confirmation
```

### setup

`check` (default) verifies the runtime prerequisites (Node.js for the hook launcher, Python 3.10+ for the catch-up, `jq` for
the SessionStart hook's stdin parsing, `claude` on PATH for the analysis leg) and reports the effective
`userConfig` values, flagging the two hazards (`observer_analysis_bare` on an OAuth-login install;
`observer_idle_seconds` below the machine's longest single turn). It also validates the repository's
`docs/conventions/session-flow.yaml`, reporting a problem as a warning. Observer reconfiguration
routes through Claude Code's native `/plugin configure session-flow@<marketplace>`; setup never
writes it. `apply` writes `docs/conventions/session-flow.yaml` and nothing else: every value and the
whole file are checked against the schema first, and changing an existing file shows the diff and
waits for your yes.

```shell
/session-flow:setup                                    # verify observer prerequisites + config (read-only)
/session-flow:setup apply worker_continuation=respawn  # write the repository setting
```

## Consumer conventions

The skills adapt to the consuming repo rather than imposing structure:

- **Stage skills**. `workflow` routes to the repo's own stage skills when they exist; every stage
  degrades gracefully to inline execution.
- **Artifact location**. `handoff` and `workflow` honor a repo-documented convention for
  save-points/work journals (the repo's `CLAUDE.md` / rules); the defaults are `.work/handoffs/`
  for handoff save-points and `.work/<slug>/workflow-checklist.md` for the per-topic workflow
  checklist, memory tier, self-ignoring and never committed.
- **Quality gates and conventions**. Build/test/lint commands, review criteria, and codification
  targets all come from the consuming repo's own instruction files.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install session-flow@melodic-software
```

## Requirements

- Node.js on PATH: every hook launches through `node hooks/exec-bash.mjs`, so without it the hooks do not run.
- The observer's catch-up only: Python 3.10+, `jq`, and `claude` on PATH. `/session-flow:setup` checks each.
- `/session-flow:find-handoff` uses Python 3.10+ when present to tell which transcript directories
  belong to this repository; without it, it lists only directories whose name matches a worktree
  exactly and says so.
- `/session-flow:recall` needs Python 3.10+ for its transcript scan; it uses `git` and `gh` when
  present for reverted commits and closed pull requests, and names any source it could not use.

## Configuration

`userConfig`. The **session observer** has nine keys, all defaulting to zero-config behavior
(see `reference/observer.md` for full semantics); **audit-sessions** has five `audit_sessions_*`
keys (store retention, excerpt length, the short-turn word limit, and the two drift-check bounds);
`cloud_route` and `retro_offer` set whether the workflow's continuation advice offers a cloud
session and whether its wrap-up offers a retro, and `implementation_route` where it sends work
after decompose; the six `away_*` keys set `/session-flow:step-away`'s
night start, report-by times, days off, watched folders and orchestrator posture; nine more keys tune single skills, and
"Option details" explains `worker_continuation`, `wip_commit`, `retro_lenses` and
`transcript_scope`. Every key is in the options reference below. The observer keys:

| Key | Default | Effect |
|---|---|---|
| `observer_enabled` | `false` | Turns on the live checks and the catch-up. Off = installing the plugin changes nothing. |
| `observer_step_check` | `true` | Live check every `observer_step_every` model steps of a turn. |
| `observer_turn_end_check` | `false` | Live check at the end of each tool-using turn; off until its cost is measured. |
| `observer_analysis_enabled` | `true` | Run the catch-up for ended sessions with no live checks. Off = no catch-up; live checks unaffected. |
| `observer_analysis_model` | see options reference | Catch-up analysis model, chosen for faithful findings; with effort, the dominant cost lever. |
| `observer_analysis_effort` | see options reference | Catch-up analysis effort, passed as `--effort` and pinned through `--settings` against a `CLAUDE_CODE_EFFORT_LEVEL` from a lower-ranked source; for which sources rank higher, see [env-vars: precedence](https://code.claude.com/docs/en/env-vars#precedence). |
| `observer_analysis_bare` | `false` | Pass `--bare` to the analysis run (breaks OAuth-login auth; leave off unless auth is an env-var API key). |
| `observer_min_lines` | `300` | Skip the catch-up for a not-yet-analyzed session with fewer transcript lines, such as an automated sweep; the skip is recorded in the observer's status file. `0` analyzes every session. |
| `observer_idle_seconds` | `900` | How long a transcript must be unchanged before the catch-up treats its session as ended; keep above the longest single turn. |

State: retro score history persists under the plugin's `${CLAUDE_PLUGIN_DATA}` directory (per-project
files), never in the consumer's repo. The audit-sessions store and reports live under
`${CLAUDE_PLUGIN_DATA}/audit-sessions/` (layout in `skills/audit-sessions/reference/store-layout.md`);
uninstalling the plugin from its last scope deletes them unless you pass `--keep-data`. The observer's per-session live-check usage files and the catch-up's transient distilled
observations live under `${CLAUDE_PLUGIN_DATA}/session-flow-observer/`; observations are deleted after each analysis run. Handoff
save-points (`.work/handoffs/` by default) and running-retro ledgers (`.work/running-retros/` by
default, shared by in-session checkpoints and the observer) are memory-tier working files
in the consumer's project: machine-local, never committed.

Network: `reanchor` queries live host state via `git`/`gh` to verify a session's referenced
PRs/issues/branches and installed-vs-repo plugin versions, degrading to reporting what it could not
verify when that authenticated egress is unavailable. `clean-stop` pushes unpushed commits and creates
or updates PRs and issues over the network via `git push` and `gh`, routing through whatever
pull-request / work-item capabilities are installed and falling back to direct `git`/`gh`. `orient`
optionally runs `gh pr list` (read-only) and, when a work-item tracker capability is installed, reads
its open items, degrading to local git state alone when `gh` or the tracker is absent. `recall`
scans local transcripts and git history, and optionally runs `gh pr list` (read-only) for closed
unmerged pull requests and searches the tracker when one is installed, naming any source it could
not reach. With `observer_enabled` on, the observer's live checks are model
calls on the session's own connection, and its catch-up runs a headless `claude -p` (ordinary model
API egress) unless `observer_analysis_enabled` is off; the in-session checkpoint is network-free. Every skill not named above is network-free
(retro, running-retro and audit-sessions read local `~/.claude/projects/` transcripts with stdlib-only
Python 3.10+ scripts sharing one transcript reader; find-handoff scans those same local transcripts read-only, using
that reader only to read the launch `cwd` that maps a scope to directories, and `reconcile` reads them read-only and mutates only the in-session task ledger);
`continue-in-background` spawns a local `claude --bg` process, a new Claude Code session with ordinary
session network access, or with `--cloud` a `claude --cloud` process that starts a cloud session
from the pushed branch, but the skill itself performs no egress.

### Option details

**`observer_analysis_enabled`.** Off, no catch-up runs, so ended sessions without live checks get
no ledger and no catch-up spend.

**`observer_analysis_bare`.** Turn it on only where auth is an env-var API key that survives
`--bare`.

**`worker_continuation`.** Read by `/session-flow:orchestrate` when it primes a session: `resume`
(default) keeps a worker across related units, `respawn` starts each new unit in a fresh worker
with consolidated scope. A repository sets it for everyone with `worker_continuation: respawn` in
`docs/conventions/session-flow.yaml` (schema: `schemas/session-flow.schema.json`), which wins over
the option; an invalid value is named and its layer dropped, so a valid higher layer still wins,
else the default `resume`, never a lower layer's value. `/session-flow:setup apply
worker_continuation=<value>` writes that file after validating it. Resolution and the root rule:
[`reference/config.md`](reference/config.md). Picking a value from a list needs Claude Code
v2.1.271 or later.

**`wip_commit`.** Read by `/session-flow:handoff`, and only when you ask in the session to pause.
On (`true`), the handoff makes one local `chore(wip): <one-line state>` commit of the tracked files
the work changed, records its SHA in the save-point and lists untracked paths there. It never
pushes, never skips commit hooks (a rejecting hook leaves the work uncommitted and the save-point
says so), and refuses on the default branch, a detached HEAD, during a merge, rebase, cherry-pick
or revert, and over a partially staged path. A handoff another skill, a hook or a phase boundary
starts never commits. Default `false`. It resolves like `worker_continuation`, from the same
`docs/conventions/session-flow.yaml`, where only an unquoted `true` or `false` is valid, and
`/session-flow:setup apply wip_commit=true` writes it.

**`retro_lenses`.** Read by `/session-flow:retro` session mode before its Phase 2 analysis. `1`
(default) runs one pass, in a fresh-context subagent that also proposes the scores unless the
`verification` level is `light` or `off`. `3` runs three subagents in parallel, one on the calls the session made
and why, one on the tools and steps it used, one on the approaches it did not try, and merges their
findings before anything is scored; it applies to short sessions too. It resolves like
`worker_continuation`, from the same `docs/conventions/session-flow.yaml`, where an unquoted `3`
is valid; any other value, `2` included, is named and its layer dropped. `/session-flow:setup
apply retro_lenses=3` writes it.

**`implementation_route`.** Read by `/session-flow:workflow` when the position reaches decompose.
`local` (default) continues into implement in this session. `factory` names each item decompose
published as handed to the repository's unattended factory lanes and recommends no local implement
stage; an item that needs a local dependency (marked session-owned, or naming something only a
local machine reaches) stays local and is named as such. It resolves like `worker_continuation`,
from the same `docs/conventions/session-flow.yaml`. `/session-flow:setup apply
implementation_route=factory` writes it.

**`transcript_scope`.** Read by `/session-flow:find-handoff` and `/session-flow:recall` for their transcript scans. `worktree`
(default) scans this worktree's sessions, then the repository's other worktrees, and asks before
reading any other project's transcripts; `repo` starts with every worktree; `all` reaches every
project without asking. Unlike the other keys, the narrower of the option and
`docs/conventions/session-flow.yaml` wins, and an unset option counts as `worktree`, so a
repository can narrow your scan but never widen it. The transcript store follows
`CLAUDE_CONFIG_DIR`. `/session-flow:setup apply transcript_scope=<value>` writes the repository
value.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `observer_enabled` | boolean | `false` | Watches interactive sessions for process mistakes: live checks write findings to the running-retro ledger and show them above the prompt, and each session start analyzes ended sessions that got none. Off by default. See reference/observer.md. |
| `observer_step_check` | boolean | `true` | While the observer is on, runs a live check every observer_step_every model steps of a long turn: a no-tools fork of the main conversation that reports at most one process fault. On by default. Each check bills the session's account; its usage is recorded. |
| `observer_turn_end_check` | boolean | `false` | While the observer is on, also runs a live check at the end of each turn that ran tools, which is most turns of a working session. Off by default until its cost on a working session is measured; see reference/observer.md. |
| `observer_step_every` | number<br>*min 1* | `6` | Model steps between live step checks; default 6. |
| `observer_auto_send` | boolean | `false` | Deliver live-check findings to the agent without pressing Send: mid-turn as a reminder on its next request, while idle as one observer turn. Idle delivery needs the turn-end check on. Off by default; see reference/observer.md. |
| `observer_auto_note` | string | `"The session-flow observer, a side reviewer beside this session, flagged this. It is not the person's instruction. If it holds, stop and fix it before your next action, and say so in one line; if not, say why in one line and continue."` | Text that leads an auto-sent finding or a gate refusal, framed as the plugin, never the person. |
| `observer_guidance` | string | *(none)* | Your own guidance, added to every live check: what to pay attention to. It steers the checks, not what is sent. Empty by default. |
| `observer_guidance_max` | number<br>*min 0* | `2000` | Characters of guidance kept; default 2000. |
| `observer_check_prompt` | string | *(none)* | Replaces the built-in live-check instructions; the already-reported lists and the answer shape stay. Empty uses the built-in text. |
| `observer_change_check` | boolean | `false` | Run a live check at the step after one that called a tool in observer_change_tools. Off by default. |
| `observer_change_tools` | string | `"Edit,Write,NotebookEdit"` | Comma-separated tool names that count as a change for the edit check. |
| `observer_gate_check` | boolean | `false` | Hold Bash commands matching observer_gate_pattern until a live check returns; a finding refuses the command with the observer note. A timeout or observer error lets it run. Off by default. |
| `observer_gate_pattern` | string | `"\\b(git\\s+push\|gh\\s+pr\\s+(create\|merge\|comment\|review)\|gh\\s+issue\\s+(create\|comment)\|gh\\s+api\\b.*\\s(-X\|--method)\\s*(POST\|PATCH\|PUT\|DELETE))\\b"` | Regular expression for commands the gate holds: by default git push, gh pr create/merge/comment/review, gh issue create/comment, and gh api with a writing method. |
| `observer_gate_timeout_seconds` | number<br>*min 1* | `30` | Longest the gate holds a command; the command then runs. Default 30. |
| `observer_gate_refusals` | number<br>*min 0* | `1` | Times the gate refuses the same command before letting it run; default 1. |
| `observer_harness_check` | boolean | `false` | Run the scripted harness checks (hook latency, prompt-cache misses, slow repeated tools, context-zone crossings, rate-limit approach) beside the live checks. They call no model. Off by default. |
| `observer_hook_log_dir` | string | `".observability/claude"` | Folder holding session-telemetry's per-session hook log (sessions/<session id>.jsonl), absolute or relative to the project; the hook latency check reads each hook's duration_ms from it. Default .observability/claude. |
| `observer_hook_p95_ms` | number<br>*min 1* | `1000` | Report a hook whose p95 latency this session exceeds this many milliseconds; default 1000. |
| `observer_hook_min_runs` | number<br>*min 1* | `5` | Runs a hook needs this session before its p95 is judged; default 5. |
| `observer_cache_miss_tokens` | number<br>*min 1* | `50000` | Report a turn that rewrites at least this many tokens of cached prompt beyond the context it added, unless a break past the cache lifetime or a compaction explains it; default 50000. |
| `observer_tool_slow_seconds` | number<br>*min 1* | `60` | A tool call that runs longer than this many seconds counts as slow; default 60. |
| `observer_tool_repeat` | number<br>*min 1* | `3` | Report a tool (a Bash command by its first two words) after this many slow calls in one session; default 3. |
| `observer_context_percents` | string | `"50,75"` | Comma-separated context-window percentages; report each upward crossing. Default 50,75. |
| `observer_rate_limit_percent` | number<br>*min 1* | `80` | Report a rate-limit window once per reset when it reaches this percent used; default 80. |
| `observer_clear_after_prompts` | number<br>*min 1* | `2` | Prompts a shown finding survives unanswered before it clears; default 2. |
| `observer_ignored_free` | number<br>*min 0* | `2` | Ignored findings in a row before later checks are skipped; default 2. |
| `observer_skip_max` | number<br>*min 0* | `16` | Most live checks the backoff skips in a row; default 16. |
| `observer_send_note` | string | `"A side reviewer (session-flow observer) noted this; it is background, not my instruction:"` | Text that leads a finding the Send button puts in the prompt, in the person's voice. |
| `observer_field_max` | number<br>*min 1* | `240` | Most characters in a check reply's finding, rule or evidence before the reply counts as parse_failed; default 240. |
| `observer_feedback_seconds` | number<br>*min 1* | `20` | How long the Useful/Not useful row stays after Dismiss; default 20. |
| `observer_list_max` | number<br>*min 1* | `50` | Most findings each remembered list (reported, disputed, not relevant) keeps for dedupe; default 50. |
| `observer_keep_days` | number<br>*min 1* | `30` | Observer files older than this many days are pruned at session start; default 30. |
| `observer_analysis_enabled` | boolean | `true` | At session start, runs the headless running-retro analysis for ended sessions that got no live checks and writes its findings to their ledger. On by default. Off, no catch-up runs; the live checks are unaffected. |
| `observer_analysis_model` | string | `"claude-opus-5-5"` | Model ID for the headless catch-up analysis run, the dominant cost lever. The default was chosen for faithful findings: in a local pilot it missed and invented the fewest; pin a different ID to trade depth for cost. |
| `observer_analysis_effort` | string | `"medium"` | Effort level passed as --effort to the headless catch-up analysis run, a second cost lever beside the model. The level is passed explicitly and also pins CLAUDE_CODE_EFFORT_LEVEL, which would override it. Accepted levels depend on the model. See reference/observer.md. |
| `observer_analysis_bare` | boolean | `false` | Passes --bare to the analysis run, dropping auto-discovery as a further cost lever. Off by default because --bare fails on OAuth-login installs (the run reports Not logged in); turn it on only where auth is an env-var API key. See reference/observer.md. |
| `observer_min_lines` | number<br>*min 0* | `300` | Transcript lines an ended session needs before its first catch-up analysis; default 300. A shorter session, such as an automated sweep, is skipped and the skip recorded in the observer's status file. A follow-up to an analyzed session is always analyzed. 0 analyzes every session. |
| `observer_idle_seconds` | number | `900` | How long a transcript must go unchanged before the catch-up treats its session as ended; default 900. Keep it above the longest single turn, or a session still mid-turn in another terminal is analyzed early. |
| `audit_sessions_retention_days` | number<br>*min 0* | `180` | How long audit-sessions keeps a session's record in its local store after the session ended; default 180. 0 keeps every record. Collect drops older records and never ingests a session already past the window. |
| `audit_sessions_excerpt_chars` | number<br>*min 0, max 600* | `240` | Longest redacted excerpt of a short typed turn that audit-sessions stores; default 240, maximum 600. 0 stores no excerpt text at all. Redaction always runs first and cannot be turned off. |
| `audit_sessions_excerpt_words` | number<br>*min 1, max 200* | `60` | A typed turn of this many words or fewer, right after a Claude reply, is flagged and excerpted by audit-sessions; default 60. These are the turns most likely to be corrections. |
| `audit_sessions_drift_min_count` | number<br>*min 1* | `20` | How often a transcript key must appear in a Claude Code version before audit-sessions' drift check reports it as new or vanished; default 20. Raise it if rare keys clutter the drift section. |
| `audit_sessions_drift_versions` | number<br>*min 1, max 20* | `3` | How many of the newest Claude Code versions a key must be absent from before audit-sessions' drift check reports it vanished; default 3, maximum 20. |
| `worker_continuation` | string | `"resume"` | How /session-flow:orchestrate runs a worker's next unit: resume (default) continues the same worker; respawn starts a fresh worker with consolidated scope unless that worker holds state costly to move. A repository's worker_continuation in docs/conventions/session-flow.yaml wins. |
| `wip_commit` | boolean | `false` | When you ask to pause, /session-flow:handoff makes one local chore(wip): commit of the tracked work. Off by default. Never pushed or run with hooks skipped; refused on the default branch, a detached HEAD, mid-merge or rebase, or a partial staging. docs/conventions/session-flow.yaml wins. |
| `transcript_scope` | string | `"worktree"` | How far /session-flow:find-handoff and /session-flow:recall read transcripts: worktree widens to the repo's other worktrees, then asks before other projects; repo starts with every worktree; all reaches every project unasked. The narrower of this and docs/conventions/session-flow.yaml wins. |
| `recall_report_kinds` | string | `"Bug"` | Comma-separated issue types or labels /session-flow:recall counts as an incident or a user report when it lists what is still reported; default Bug, which also matches a type: bug label. docs/conventions/session-flow.yaml wins. |
| `recall_doc_paths` | string | `"*.md"` | Comma-separated git pathspecs /session-flow:recall searches for postmortems on the topic; default *.md, every tracked markdown file. docs/conventions/session-flow.yaml wins. |
| `retro_lenses` | string | `"1"` | How many review passes /session-flow:retro session mode runs: 1 (default) one pass; 3 three parallel subagents (the calls made and why, the tools and steps used, the approaches not tried), merged before scoring. docs/conventions/session-flow.yaml wins. |
| `lane_transcript_sink` | directory | *(none)* | The private directory holding pulled CI lane transcripts and their metrics.jsonl, read by /session-flow:retro ci-runs and /session-flow:audit-sessions pr. Unset: ci-runs needs --sink and audit-sessions pr skips CI legs; there is no default location. A --sink given on the command line wins. |
| `cloud_route` | string | `"offer"` | Whether /session-flow:workflow's end-of-phase continuation advice offers a cloud session when the next chunk of work fits one. offer (default) names it with the reason; off never mentions it. Advice only: nothing launches a cloud session unless you ask. |
| `retro_offer` | string | `"offer"` | Whether /session-flow:workflow's end-of-session wrap-up offers a retrospective. offer (default) suggests /session-flow:retro for substantive sessions; off never offers one. Offer only: nothing runs a retro unless you ask. |
| `implementation_route` | string | `"local"` | Where /session-flow:workflow sends work after decompose. local (default) continues into implement here; factory hands published items to the repository's unattended factory lanes, keeping local only items that need a local dependency. docs/conventions/session-flow.yaml wins. |
| `recommend_skills_exclude` | string | `"none"` | Which skill states /session-flow:recommend-skills leaves out of its menu: none (default) names every skill, annotating disabled and not-installed ones; the others drop disabled skills, skills not installed, or both. The menu says which states it dropped. |
| `orient_catch_up_word_cap` | number<br>*min 150* | `250` | Most words /session-flow:orient catch-up may use for what happened, visuals excluded; default 250, minimum 150. Every action item is listed in full whatever the cap. The reply opens with what needs you, then what happened, then each decision. |
| `away_night_start` | string | `"21:00"` | Local time of day, HH:MM, when /session-flow:step-away bed treats the night as starting; default 21:00. The night window runs from this time to the next report-by time. A time named in the launch words wins. |
| `away_report_by_workday` | string | `"09:00"` | Local time of day, HH:MM, by which /session-flow:step-away has its return report ready on a workday; default 09:00. A time named in the launch words wins. |
| `away_report_by_day_off` | string | `"10:00"` | Local time of day, HH:MM, by which /session-flow:step-away has its return report ready on a day off; default 10:00. A time named in the launch words wins. |
| `away_days_off` | string | `"Sat,Sun"` | Comma-separated three-letter weekday names /session-flow:step-away treats as days off when it picks the report-by time; default Sat,Sun. |
| `away_watched_folders` | string | *(none)* | Comma-separated folders /session-flow:step-away scans for files written while you are away; empty (default) scans the home folder. Dot folders and git work trees are skipped. |
| `compact_focus_enabled` | boolean | `true` | Records a typed /goal, a resumed handoff file and a step-away task file and posture in this session's focus file, and prints that file before each compaction so the summary keeps them. On by default. Your own value wins over docs/conventions/session-flow.yaml. |
| `resume_context_enabled` | boolean | `true` | When a pasted resume prompt starts with its handoff directive, adds the resume procedure to that turn once per session: raise due reminders, reconcile recorded off-thread work, re-arm loops, cron tasks and monitors. On by default. Your own value wins over docs/conventions/session-flow.yaml. |
| `away_orchestrate` | boolean | `false` | When on, /session-flow:step-away runs every absence as an orchestrator: the main session delegates work and keeps only briefs, verdicts and state in its context, so it rides compaction through a long run. Off by default. Words in the launch line can turn it on or off for one run. |

### How to set these

Set the options above for `session-flow@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->
