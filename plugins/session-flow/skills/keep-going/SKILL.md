---
name: keep-going
description: "Recover and continue after any interruption — rate limit, crash, disconnect, or a gap. Inventory off-thread work, inspect its real state, resume or restart it, then continue the main task where it stood. Use when: 'keep going', 'continue', 'pick up where you left off', 'resume', 'you got cut off', 'we got interrupted', 'carry on', 'what were you doing'. Auto-resumes safe work; gates re-running anything with side effects."
user-invocable: true
disable-model-invocation: false
---

# Keep going

## Purpose

After an interruption — a rate limit, a crash, a disconnect, or just a
long gap — work started off the main thread may be paused, dead, or
silently finished, and the main task's position is easy to misremember.
This skill recovers the off-thread work, reconciles the main thread from
its real state rather than assumption, and continues. Scope is general:
the recovery is the same whatever caused the interruption, so the cause
is not diagnosed here.

Where `/session-flow:handoff` deliberately pauses a session, keep-going is
the resume counterpart — it picks the work back up after any pause, planned
or not.

## Steps

1. **Inventory off-thread work.** Enumerate everything that was running
   outside this thread. On the current harness that includes background
   tasks, background shell commands, monitors, scheduled / cron tasks,
   dynamic workflows, and spawned subagents — treat that list as
   examples of the *kinds* of off-thread work to find, not a fixed
   catalogue; the tool surface evolves, so inventory whatever mechanisms
   exist now.
2. **Inspect real state — never assume.** For each item, read its actual
   state from the source of truth: task output, journals, transcripts,
   shell logs, monitor status. Do not infer "it probably finished" or
   "it probably died" — check. An interruption can leave work completed,
   mid-flight, or dead, and only the artifact tells you which.
3. **Recover per item.** Classify and act:
   - **Resumable** → resume it. Prefer a real resume over a restart when
     the mechanism supports one (e.g. a workflow resume reuses the cached
     prefix instead of redoing work).
   - **Dead but safe to redo** → restart it (subject to the autonomy
     policy below).
   - **Unrecoverable** → surface it plainly; do not fake a recovery.
4. **Reconcile the main thread.** Restate where the primary task actually
   stood — grounded in a fresh read of any plan / checklist / task
   artifact backing it, not a prior turn's claim — then continue it. When
   the interruption followed a `/session-flow:handoff`, the handoff file is
   that artifact; read it rather than trusting memory.
5. **Report.** One list: recovered, restarted, still-running, and lost /
   unrecoverable.

## Autonomy policy — resume freely, gate re-fires

- **Auto-resume** safe, idempotent, read-only, or clearly incomplete
  work without asking. That is the default; recovery should not stall on
  confirmation for work that cannot double-fire.
- **GATE** before RE-RUNNING anything with external side effects — a
  push, a PR comment, a sent message, a deploy, a mutation — where a
  re-fire could duplicate the effect. When the inspection in step 2
  cannot prove the action did NOT already land, stop and ask before
  repeating it. Double-firing a side effect is worse than pausing.

## Nothing-off-thread case

If the inventory finds no off-thread work, say so and go straight to
step 4: reconcile the main thread from its real state and continue. The
interruption may have hit mid-turn on the main thread alone — recovering
that is still the job.

## What this skill does NOT do

- **Does not diagnose the interruption type.** Whether it was a short
  limit, a weekly limit, or a crash does not change the recovery, so it
  is not classified here.
- **Does not blindly restart side-effectful work.** Re-firing is gated
  by the autonomy policy, not automatic.
- **Does not trust remembered state.** Every status claim is grounded in
  a fresh read of the real artifact.

## Gotchas

- The specific tools that hold off-thread work change over time; the
  duty is to inventory whatever off-thread mechanisms the current
  harness exposes, not to look only for the ones named above.
- "Probably done" is the failure mode. A resumable job that looks
  finished may have died at 90%; a side-effect that looks unsent may
  have landed just before the cutoff. Read the artifact both ways.
