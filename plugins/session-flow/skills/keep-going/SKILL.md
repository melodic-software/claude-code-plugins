---
name: keep-going
description: "Recover and continue after an interruption — rate limit, crash, disconnect, or gap — or when live off-thread work looks stalled and you are asked to check on it. Inventory off-thread work, inspect its REAL output, act only on evidence (resume / rerun / kill-and-restart), then continue the main task where it stood. Use when: 'keep going', 'continue', 'pick up where you left off', 'resume', 'you got cut off', 'we got interrupted', 'carry on', 'what were you doing', 'check the monitor', 'stop staring at it', 'poke it', 'is it stuck', 'are you stuck'. Infers intent from the conversation; arguments optional. After a usage limit lifts it continues rather than summarizing-and-stalling; it gates killing or re-firing side-effectful work."
user-invocable: true
disable-model-invocation: false
---

# Keep going

## Purpose

After an interruption — a rate limit, a crash, a disconnect, or just a
long gap — work started off the main thread may be paused, dead, or
silently finished, and the main task's position is easy to misremember.
The same recovery also applies live, mid-session, when off-thread work
*looks* stalled and someone asks you to check on it. This skill recovers
or verifies the off-thread work from its **real** state, reconciles the
main thread, and continues. Scope is general: the recovery is the same
whatever caused the interruption, so the cause is not diagnosed here.

Two failure modes this skill exists to prevent: **summarizing and
stalling** once a usage limit has lifted instead of continuing, and
**killing live-but-slow work on a hunch** instead of on evidence.

Where `/session-flow:handoff` deliberately pauses a session, keep-going is
the resume counterpart — it picks the work back up after any pause, planned
or not.

## Two ways in — same flow

1. **After an interruption** — a rate limit, crash, disconnect, or gap
   left work in an unknown state.
2. **A live-session poke** — nothing was necessarily interrupted, but
   off-thread work looks stalled and you are asked to check ("check the
   monitor", "poke it", "is it stuck", "stop staring at it"). Verify
   against real output *before* acting; it may be alive and progressing.

Either way the flow is identical: inventory → inspect the real state →
act on evidence → continue.

## Intent comes from the conversation, not the arguments

Infer *what* to resume or check from the conversation and the real
off-thread state, not from an argument. Arguments only narrow the target;
their absence never blocks. When the conversation makes the referent
clear, do not stop to ask "what should I keep going on?" — that stall is
itself the thing this skill removes.

## Steps

1. **Inventory off-thread work.** Enumerate everything running outside
   this thread — background tasks, background shell commands, monitors,
   scheduled / cron tasks, dynamic workflows, spawned subagents. Treat
   that as examples of the *kinds* of off-thread work to find, not a
   fixed catalogue; the tool surface evolves, so inventory whatever
   mechanisms exist now.
2. **Inspect real state — never assume.** For each item read its actual
   state from the source of truth: task output, subagent transcript,
   monitor status, journals, shell logs. Do not infer "it probably
   finished" or "it probably died" — check. Only the artifact tells you
   which.
3. **Recover per item — act on evidence.** Classify against the real
   output and act:
   - **Progressing** (even if slow) → leave it; report it is alive and
     moving. Do not kill work that is making progress.
   - **Resumable** → resume it. Prefer a real resume over a restart when
     the mechanism supports one (a workflow resume reuses the cached
     prefix instead of redoing work).
   - **Dead but safe to redo** → restart it (subject to the autonomy
     policy below).
   - **Unrecoverable** → surface it plainly; do not fake a recovery.
4. **Reconcile the main thread.** Restate where the primary task actually
   stood — grounded in a fresh read of any plan / checklist / task
   artifact backing it, not a prior turn's claim — then continue it. When
   the interruption followed a `/session-flow:handoff`, read that file
   rather than trusting memory — and when the handoff's path was lost (a
   `/clear` without copying the resume prompt), recover it first with
   `/session-flow:find-handoff`.
5. **Report.** One list: recovered, restarted, still-running, and lost /
   unrecoverable.

## Active-verification protocol — evidence before action

For any "is it stuck / check the monitor / poke it":

- **Read the real output first** — monitor status, subagent
  transcript/output, task output, shell logs. Judge from the artifact,
  never from "it has been a while."
- **Progress-vs-elapsed is a suspicion-raiser only.** Slow relative to
  elapsed time tells you to look closer; it never by itself authorizes a
  kill. Confirm "dead" or "stuck" against the actual output.
- **When the evidence is ambiguous, treat the work as alive.** Killing
  live-but-slow work that was actually progressing is the failure mode to
  guard against.

## Autonomy policy — resume freely, gate side effects

- **Auto-resume** safe, idempotent, read-only, or clearly incomplete
  work without asking. Recovery should not stall on confirmation for work
  that cannot double-fire.
- **GATE** before RE-FIRING anything with external side effects — a push,
  a PR comment, a sent message, a deploy, a mutation — **and** before
  KILLING or RESTARTING off-thread work whose death you cannot prove from
  step 2. When the inspection cannot prove the action did NOT already
  land, or cannot prove the work is actually dead, stop and ask.
  Double-firing a side effect, or killing live work, is worse than
  pausing.

## After a usage limit lifts — GO, don't summarize

- If you are executing again, the block is already over: **continue the
  work**. Do not produce a summary and stop — summarize-and-stall is the
  failure mode. Report only at the end or on a hard block.
- The time-vs-reset check belongs to the **orchestration** case: when
  step 2 inspects a worker or subagent that is itself limited, compare the
  current time against the reset its limit message states, to decide
  whether that worker can proceed now. In a single interactive session,
  if you are running, the answer is already GO.
- Reset information available in-session is the limit **message text**
  only (e.g. `resets 3:45pm`) and the interactive `/usage` view — there is
  no environment variable, file, or API that exposes it. Read the reset
  from the message; never invent a window.

## Still blocked (limit not yet reset) — hand back, don't busy-wait

While a limit still holds you cannot make progress in this session.
Compose with `/session-flow:handoff` to drop a resume artifact so nothing
is lost, then stop. Automatic wake-and-continue at the reset time is an
external scheduler's job — a desktop scheduled task or a cloud routine
launched to resume from that handoff — not this skill's; keep-going hands
back cleanly and stops.

## Nothing-off-thread case

If the inventory finds no off-thread work, say so and go straight to
step 4: reconcile the main thread from its real state and continue. The
interruption may have hit mid-turn on the main thread alone — recovering
that is still the job.

## What this skill does NOT do

- **Does not diagnose the interruption type.** A short limit, a weekly
  limit, or a crash all take the same recovery, so the cause is not
  classified. (Reading a stated reset time to gate a blocked worker is not
  diagnosis — it does not change the recovery method.)
- **Does not kill or restart live-but-slow work on a hunch.** Action
  follows real output, and kill/restart is gated like any side effect.
- **Does not summarize-and-stall after a limit lifts** — it continues.
- **Does not build or arm its own scheduler.** Still-blocked work is
  handed back via `/session-flow:handoff`, not parked on a self-armed
  wakeup.
- **Does not trust remembered state.** Every status claim is grounded in
  a fresh read of the real artifact.

## Gotchas

- The specific tools that hold off-thread work change over time; inventory
  whatever off-thread mechanisms the current harness exposes, not only the
  ones named above.
- "Probably done" is one failure mode; "it has been a while, kill it" is
  the other. A resumable job that looks finished may have died at 90%; a
  side-effect that looks unsent may have landed just before the cutoff;
  live-but-slow work that looks hung may be one step from done. Read the
  artifact before you decide.
- After a limit lifts, the pull is to summarize and hand back. Resist it:
  if you are running, continue, and report at the end.
