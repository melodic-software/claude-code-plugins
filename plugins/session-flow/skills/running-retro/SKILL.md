---
name: running-retro
description: "Take an in-flight retrospective checkpoint mid-session: spawn a subagent to analyze the session transcript so far (reusing retro's parser), classify each finding by category and suggested resolution route (CLAUDE.md fix / rule fix / skill change / new-skill candidate / tracker issue), and append it to a cumulative running ledger — capture and route only, never auto-applied. The live counterpart to /session-flow:retro, which is the end-of-session full scoring + codification pass. An `arm` action instead launches a detached observer that watches this session out-of-band and runs the checkpoint autonomously after the session ends (zero context cost; findings land in the same ledger). Use when: 'running retro', 'live retro', 'in-flight retro', 'checkpoint this session', 'how is this session going', 'observe the session so far', 'arm the observer', 'watch this session in the background', 'observe this session after it ends', partway through a long skill loop, or on a /loop interval. Does NOT score the session, codify learnings (that is /session-flow:retro codify), auto-file issues, or /clear the session."
argument-hint: "[topic | arm] (e.g., /running-retro, /running-retro phase-3, /running-retro arm)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Claude session: !`echo "${CLAUDE_CODE_SESSION_ID:-unknown}" || echo "unknown"`

## Repository context — gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch — `git branch --show-current`
- Recent commits — `git log --oneline -5`
- Working tree status — `git status --porcelain`, reading **at most the first 20 entries**

Honor that 20-entry bound when reading; do not restore it as a `| head -20` pipe. A piped git
command is compound, which is the shape #1619 is about — bounding at read time keeps the cap without
reintroducing the defect.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. These moved
out of pre-compute in #1619 — the harness composes the block into one shell invocation and a
worktree-isolated agent refuses a git-bearing compound command; do not fold them back.

## Purpose

The self-improvement loop, run **while the work is still in flight** — not after it. Answers, at a
mid-session checkpoint: "How is this session actually going, what is drifting, and what should
change before it costs more?" Each checkpoint appends to a cumulative **running ledger** for the
session, so observations accumulate across a long session or a `/loop` interval rather than waiting
for a single end-of-session pass.

It **captures and routes** findings; it does not apply them. Codification (editing `CLAUDE.md`,
rules, or memory) stays with `/session-flow:retro codify`. Tracker filing is offered, never
performed automatically.

## Siblings — pick the right one

- **`/session-flow:retro`** — end-of-session full retrospective: five scored dimensions, feedback
  regression check, codification of approved learnings. running-retro is its live counterpart:
  same act (retrospective), different cadence (mid-flight, cumulative), and it deliberately drops
  scoring and codification.
- **`/session-flow:handoff`** — a save-point that ends the session for `/clear`. running-retro is
  **non-terminating**: it observes and the session keeps going.

## Zero-arm — nothing to set up in advance

No arming at session start for the default in-session checkpoint. The session transcript on disk
(`<session-id>.jsonl`) is the lossless record — it survives compaction, so a checkpoint reconstructs
the full session from disk even after the live context was compacted. That is exactly what
`/session-flow:retro`'s parser already reads in production; running-retro reuses it rather than
parsing anew. Invoke a checkpoint any time. (The `arm` action and its opt-in SessionStart hook are
the deliberate exception — they arm a detached observer to run the checkpoint *after* the session
ends; see "Arming a detached observer" below. The default checkpoint still needs no setup.)

## The checkpoint flow

### 1. Subjective-state note (main agent — the one thing disk cannot capture)

Before delegating, write **2-3 lines** of your own in-flight state: what you are uncertain about,
what feels off, where you are stuck or repeating, any correction you sense coming. The transcript on
disk holds what *happened*; it does not hold the acting agent's present read of it. This note is the
only signal the analysis subagent cannot get for itself — it seeds the analysis.

### 2. Resolve inputs for the subagent

The analysis runs in a **fresh subagent** (own context window; it sees none of this conversation,
the skills invoked, or files read — per the sub-agents doc "what loads at startup"). So resolve
every input to a concrete value and pass it in the delegation prompt — a `${CLAUDE_PLUGIN_ROOT}`
token will NOT expand there:

- **Session data dir + transcript + subagents dir** — resolve per the retro skill's "Paths"
  (`${CLAUDE_PLUGIN_ROOT}/skills/retro/SKILL.md`); transcript is `<SESSION_DATA_DIR>/<session-id>.jsonl`,
  subagents `<SESSION_DATA_DIR>/<session-id>/subagents/`.
- **Parser (absolute path)** — resolve `${CLAUDE_PLUGIN_ROOT}/skills/retro/scripts/parse_transcript.py`
  to its absolute form and pass that; the invocation + Python-3.10+ interpreter detection live in
  retro's Phase 1.1 (`${CLAUDE_PLUGIN_ROOT}/skills/retro/context/session.md`) — point the subagent
  there, do not restate them.
- **Handoff-chain pointers** — if this session resumed from a handoff, pass the chain so the
  subagent's parser run spans the whole transcript chain, subject to the continuity gate in retro's
  Phase 1.0 (`${CLAUDE_PLUGIN_ROOT}/skills/retro/context/session.md`).
- **Prior running-retro ledger** — if this session's ledger (or its chain) carries a
  `previous_running_retro` pointer, resolve that prior ledger's absolute path and pass it so the
  subagent carries forward earlier checkpoints' findings (the "running" = cumulative guarantee). This
  is the ledger's OWN continuity chain — walked by reading the ledger files, NOT the parser's
  `--chain-from` — so a session continued from an earlier checkpoint without a handoff still keeps
  its prior findings.
- **Repo convention docs** — the consuming repo's `CLAUDE.md`, the relevant `.claude/rules/` files,
  and any convention READMEs, so the subagent judges convention/workflow drift against the repo's
  documented rules. These are trusted local reads; transcript content is not (see checkpoint.md's
  trust boundary).
- **The subjective-state note** from step 1.

### 3. Delegate the analysis

Spawn a general-purpose subagent with the delegation prompt from
[`context/checkpoint.md`](${CLAUDE_PLUGIN_ROOT}/skills/running-retro/context/checkpoint.md) — it
carries the parser-first-then-selective-read method, the finding categories, the resolution-route
classification, and the **mandatory redaction pass** on the returned findings. The subagent returns
a compact findings block only; the verbose transcript stays in its context.

### 4. Append to the running ledger

Resolve the ledger location through the plugin binding
([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)) —
`<memory_dir>/running-retros/` (default `.work/running-retros/`).

**One ledger file per session, appended — discover before creating.** Name it
`<TS>-running-retro-<topic>.md` (`TS = date -u +%Y%m%dT%H%M%SZ`, topic = argument or inferred),
created on this session's FIRST checkpoint with frontmatter `session_id: $CLAUDE_CODE_SESSION_ID`. On
every LATER checkpoint do NOT create a second file: locate this session's existing ledger by globbing
`<memory_dir>/running-retros/*-running-retro-*.md` and matching the one whose frontmatter `session_id`
equals the current `$CLAUDE_CODE_SESSION_ID`, then re-read it from disk and **append** a new
`## Checkpoint <TS>` section. Create a new file only when no such match exists. This session-id match
is the discovery rule that keeps one file per session rather than one per checkpoint.

**Chaining across `/clear`.** When this session resumed a prior one through a handoff chain (retro's
Phase 1.0 continuity gate), record `previous_running_retro` (the prior session's ledger path) and
`previous_session_id` in this ledger's frontmatter. These are ledger-continuity pointers THIS skill
walks to present the cumulative running history; they are NOT parser input — the parser's
`--chain-from` consumes handoff files only (it reads `session_id` / `previous_handoff`), never
running-retro ledgers. Honor the contract's runtime guards from the binding (the once-per-session
self-ignore guard on the resolved memory root; never edit the consumer's root `.gitignore`).

**Redact before writing.** Re-sweep the findings for secrets, tokens, credentials, connection
strings, and PII, replacing each with a shape marker (`<REDACTED: API key>`) — defense in depth over
the subagent's own pass. The ledger is memory-tier disk output: it outlives the session, sits
uncommitted-but-readable, and travels to other sessions and machines.

### 5. Offer routing — never auto-apply

Present the checkpoint findings, then OFFER the forward routes; act only on the ones the user picks:

- **Codify a durable learning** → `/session-flow:retro codify` (running-retro never edits
  `CLAUDE.md`, rules, or memory itself).
- **File follow-up work** → offer the consumer's work-item tracker; never file automatically.
- **Nothing actionable** → say so and continue the task.

## Post-checkpoint checklist

Tick each in the response so the exit shape is verifiable:

- [ ] Subjective-state note written before delegating (step 1)
- [ ] Analysis delegated to a fresh subagent with resolved absolute inputs (step 2-3)
- [ ] **Redaction swept the subagent findings AND the ledger append** (both hops — step 3 and step 4)
- [ ] Findings appended to this session's single ledger file (located by `session_id` match, not a
  new per-checkpoint file; self-ignore guard verified on the first memory-tier write)
- [ ] Routes offered, nothing auto-applied (step 5); the task continues in this same session

## Arming a detached observer (`arm`)

When `$ARGUMENTS` is `arm` (or the user asks to watch/observe this session in the background), do
NOT run the in-session checkpoint above. Instead launch the **detached observer** for the current
session: a substrate that outlives the session, tails its transcript out-of-band at zero context
cost, detects end by mtime-idle, and (unless analysis is disabled) runs this same checkpoint method
headless afterwards, appending its findings to this session's ledger. The substrate, lifecycle,
config, untrusted-data boundary, and the deferred native Observer-Agents alternative live in
[`${CLAUDE_PLUGIN_ROOT}/reference/observer.md`](${CLAUDE_PLUGIN_ROOT}/reference/observer.md) — read
it, do not restate it. To arm the current session, resolve the inputs and run the launcher:

First resolve these into shell variables the block below reads. A skill runs **in-session**, so read
config from the **rendered `${user_config.observer_*}` values** (an unexpanded token or empty = the
default) — the `CLAUDE_PLUGIN_OPTION_*` env vars the hook uses are NOT set in a skill's Bash context:

- `OBS_MODEL` ← `${user_config.observer_analysis_model}` (default `claude-haiku-4-5`)
- `OBS_IDLE` ← `${user_config.observer_idle_seconds}` (default `900`); `OBS_MAX` ←
  `${user_config.observer_max_seconds}` (default `86400`)
- `OBS_ANALYSIS` ← `${user_config.observer_analysis_enabled}` (default `true`) — an operator who set it
  `false` to avoid autonomous spend must NOT get a `claude -p` run from a manual arm
- `OBS_BARE` ← `${user_config.observer_analysis_bare}` (default `false`)
- `DECLARED_MEMORY_DIR` ← a `memory_dir` the consuming repo documents in prose (its `CLAUDE.md` /
  rules) but not in `.claude/topic-docs.yaml` — retro's rung-2 inference; empty otherwise. Being
  in-session, the manual arm CAN honor this (and cross-session continuity below); the headless hook
  resolves `memory_dir` only from the concern file + default and cannot infer a prose-documented root.
- `PREV_LEDGER` / `PREV_SID` ← for cross-session continuity, if this session resumed from a handoff
  chain or an earlier running-retro ledger: resolve the prior ledger and its session id under retro's
  Phase 1.0 continuity gate (same as the checkpoint flow's step 2). A detached/headless observer cannot
  make that judgement safely (blindly linking the newest handoff could splice an unrelated session), so
  the SessionStart hook leaves these empty and a later in-session checkpoint reconciles them.

The launcher resolves the ledger dir to an absolute path, so a relative `memory_dir` still lands in the
consumer repo, not the plugin cache.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
TRANSCRIPT="$SESSION_DATA_DIR/${CLAUDE_CODE_SESSION_ID}.jsonl"   # SESSION_DATA_DIR per retro's "Paths"
MEMORY_DIR=$(bash "$PLUGIN_ROOT/skills/retro/scripts/parse-concern-value.sh" \
  .claude/topic-docs.yaml memory_dir "${DECLARED_MEMORY_DIR:-}")
MEMORY_DIR="${MEMORY_DIR:-.work}"
WORK_DIR="${CLAUDE_PLUGIN_DATA:-${TEMP:-${TMPDIR:-/tmp}}}/session-flow-observer"

PY=""; for c in python3 python; do command -v "$c" >/dev/null 2>&1 \
  && "$c" -c 'import sys;sys.exit(0 if sys.version_info>=(3,10) else 1)' 2>/dev/null && { PY="$c"; break; }; done

args=(--transcript "$TRANSCRIPT" --work-dir "$WORK_DIR" --ledger-dir "$MEMORY_DIR/running-retros"
  --session-id "$CLAUDE_CODE_SESSION_ID" --plugin-root "$PLUGIN_ROOT"
  --previous-running-retro "${PREV_LEDGER:-}" --previous-session-id "${PREV_SID:-}"
  --model "${OBS_MODEL:-claude-haiku-4-5}"
  --idle-seconds "${OBS_IDLE:-900}" --max-seconds "${OBS_MAX:-86400}")
[[ "${OBS_ANALYSIS:-true}" != "false" ]] && args+=(--analysis)
[[ "${OBS_BARE:-false}" == "true" ]] && args+=(--bare)
"$PY" "$PLUGIN_ROOT/skills/running-retro/scripts/arm_observer.py" "${args[@]}"
```

This is the SAME launcher the opt-in SessionStart hook (`observer_enabled`) uses; manual `arm` works
whether or not the auto-arm is on, and is the primary entry. Because it runs in-session it can honor
prose-inferred memory roots and cross-session continuity the headless hook cannot. The launcher prints
the observer pid and returns at once; it never blocks the session.

## Cadence

Manual checkpoint by default. Composes with `/loop` for periodic checkpoints across a long session;
running-retro ships no scheduler of its own. It is non-terminating — after routing, the underlying
task continues in this same session. The detached observer (`arm`) is the push/end-of-life
counterpart: a `/loop` cannot fire after the session ends, but the observer can.

## What this skill does NOT do

- **Does not score the session** — the five scored dimensions are `/session-flow:retro`'s.
- **Does not codify learnings** — capture + route only; codification is `/session-flow:retro codify`.
- **Does not auto-file tracker issues** — it offers routing; the user decides.
- **Does not `/clear` or end the session** — unlike `handoff`; the session continues.
- **Does not run builds, tests, or a code review**, and does not write into the consumer's repo
  beyond the memory-tier ledger and any routing the user approves.

## Gotchas

- **The subjective-state note is mandatory** — skipping it discards the one input the subagent
  cannot reconstruct from disk.
- **Pass resolved absolute paths to the subagent** — its fresh context expands no plugin variables
  and inherits none of this conversation's paths.
- **Redact on both hops** — the subagent's findings pass AND the ledger write; memory-tier output
  outlives the session.
- **One ledger file per session, appended** — discover this session's file by matching `session_id`
  in frontmatter before writing (never create a second file per checkpoint); re-read from disk before
  appending, never rewriting from a possibly-stale in-context copy. Cross-`/clear` history is linked
  by the `previous_running_retro` pointer, which the skill walks — not the parser.
- **Non-terminating** — a checkpoint is an observation, not a stop point; do not treat it like a
  handoff.
