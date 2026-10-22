---
description: "Recovery after an interruption, rate limit, crash, or gap, or a check on off-thread work that looks stalled: inspects its real output, acts on evidence (resume, rerun, kill-and-restart), then continues the main task. Use when: asked to keep going, continue, or resume; 'what were you doing'; 'pick up where that agent left off'; 'check the monitor', 'is it stuck', 'stop staring at it'. Gates killing or re-firing side-effectful work. To retire finished work and reconcile the ledger instead, use /session-flow:reconcile."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: session
  summary: Recover after an interruption and continue where work stood
---

# Keep going

## Purpose

After an interruption, a rate limit, a crash, a disconnect, or just a
long gap, work started off the main thread may be paused, dead, or
silently finished, and the main task's position is easy to misremember.
The same recovery also applies live, mid-session, when off-thread work
*looks* stalled and someone asks you to check on it. This skill recovers
or verifies the off-thread work from its **real** state, reconciles the
main thread, and continues.

Two failure modes this skill exists to prevent: **summarizing and
stalling** once a usage limit has lifted instead of continuing, and
**killing live-but-slow work on a hunch** instead of on evidence.

Where `/session-flow:handoff` deliberately pauses a session, keep-going is
the resume counterpart. It picks the work back up after any pause, planned
or not.

## Two ways in, same flow

1. **After an interruption**, a rate limit, crash, disconnect, or gap
   left work in an unknown state.
2. **A live-session poke**. Nothing was necessarily interrupted, but
   off-thread work looks stalled and you are asked to check ("check the
   monitor", "poke it", "is it stuck", "stop staring at it"). Verify
   against real output *before* acting; it may be alive and progressing.

Either way the flow is identical: inventory → inspect the real state →
align on the recorded goal → act on evidence → continue.

## Intent comes from the conversation, not the arguments

Infer *what* to resume or check from the conversation and the real
off-thread state, not from an argument. Arguments only narrow the target;
their absence never blocks. When the conversation makes the referent
clear, do not stop to ask "what should I keep going on?"; that stall is
itself the thing this skill removes.

## Steps

1. **Inventory off-thread work.** Enumerate everything running outside
   this thread, per the off-thread kinds in
   [`${CLAUDE_PLUGIN_ROOT}/reference/off-thread-work.md`](${CLAUDE_PLUGIN_ROOT}/reference/off-thread-work.md)
   an open-ended set (background tasks, shells, monitors, scheduled
   jobs, dynamic workflows, subagents, external CLI processes), not a
   fixed catalogue. Single out every subagent or workflow agent whose last
   notification carries a rate-limit error type or a usage-limit message,
   and every agent the user's prompt or a branch or PR trail says ended on
   a usage limit (a gone session's notifications are not available): they
   take the rate-limited path in step 4. For each background shell, also list its child
   process tree and flag any process waiting on an interactive prompt or
   stdin, so a run hung on a `[y/N]` question is found instead of read
   as slow:

   ```shell
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/keep-going/scripts/check-child-input-wait.py" "<shell pid>"
   ```

   `<shell pid>` is the OS process id of the shell, not its task or shell
   id: take it from the pid the task reports, else find the shell with
   `ps` (its parent is the session). When no pid can be resolved, skip
   this check for that shell and say so in the report.

   It prints JSON: each descendant with its command line and a
   `waiting_on_input` verdict of `yes`, `no` or `unknown`, plus `waiting`
   and `unknown` pid lists. Exit `0`: none waiting. Exit `1`: at least one
   waiting. Exit `2`: bad argument or the pid is not running. Exit `3`:
   the process table could not be read. Exit `4`: none waiting, but some
   verdicts are `unknown`. `unknown` (an elevated process the session
   cannot inspect, a platform with no signal, or on Linux a process the
   script can read only through `/proc/<pid>/wchan`, which flags a tty
   read and nothing else) is never read as `no`: inspect that process by
   other means before calling it slow. On Linux each row also carries
   `stdin`, where fd 0 points: a Claude Code shell's children inherit
   `/dev/null`, which cannot hang on a prompt, and a `pipe:[...]` there
   is usually a pipeline waiting on its producer, not on a person. A Linux
   `yes` needs `/proc/<pid>/syscall`, which only an ancestor can read
   under Yama `ptrace_scope` 1 or higher.
2. **Inspect real state, never assume.** Read each item's actual state
   from the source of truth, per that doc's inspect-real-state invariant:
   do not infer "it probably finished" or "it probably died". Only the
   artifact tells you which. When the session that launched the work is
   gone (a crash, a restart, a closed terminal), its agent and task ids
   went with it: find the work by what it left behind, its branch, its
   PR, its worktree and commits, not by an id that no longer resolves.

   **Measure the gap first.** Run
   `python3 "${CLAUDE_PLUGIN_ROOT}/skills/keep-going/scripts/measure-stop-gap.py" "<session transcript path>"`
   on this live, resumed session's transcript; a stopped transcript no
   prompt has resumed yet is out of its scope. It prints JSON with the last assistant entry, the limit or error
   entry (null when there is none), now, and the gap from the stop to
   now (`gap`, `gap_seconds`); a transcript with no limit or error entry
   measures from the last assistant entry. Exit `2` (missing, unreadable
   or empty transcript, or no assistant entry) means the gap is unknown:
   report it as unknown, never estimate it. The snapshot's Gap field
   carries it.
   Anything remembered from before the stop and older than the gap is
   re-read, not trusted: limit windows, leases, PR state and CI runs.

   **Print the environment snapshot** once step 2's reads are done and
   before step 3 or any recovery action, as one block with these fields,
   each from its own source:
   - **Account**: the stop-time and active accounts with their sources
     and the unchanged / changed / unknown state, per "After a usage limit
     lifts"; the operator's answer stands in for a missing reading, and
     with none the field is `unknown`.
   - **Windows**: the 5-hour and 7-day windows with reset times, from
     `mcp__rate-limit-guard__status`.
   - **Zone**: the word from `mcp__context-guard__status`, per "Zone
     input".
   - **Off-thread items**: each with its liveness verdict from this step,
     or `none found`.
   - **Gap**: from `measure-stop-gap.py`.
   - **Cause**: the evidence for why the work stopped, quoted (the limit
     message, the error entry), or `none found`.

   A field with no reading says `unknown` and why (plugin not installed,
   mods off, tool answer with no windows, no transcript); a value is never
   guessed. The cause line states evidence only and picks no recovery.
3. **Goal alignment, before any recovery ACTION.** When the resume
   follows a `/session-flow:handoff`, read that file rather than trusting
   memory, and when the handoff's path was lost (a `/clear` without
   copying the resume prompt), recover it first with
   `/session-flow:find-handoff`. Read its `Original goal` section, then
   test the planned next actions against it: **say in one sentence how
   the next action serves that goal.** If you cannot, that is drift, not
   a wording problem. Stop, and either re-derive an action that does
   serve the goal or ask the user whether the goal changed. **A handoff
   carrying no `Original goal` is itself a defect:** do not infer the goal
   from the process the file describes, which is the thing that drifted,
   ask the user for it in their own words before continuing, and carry
   their answer into the next save-point.

   This check sits between inspection and action deliberately: steps 1-2
   only read, but step 4 resumes and restarts work, and restarting work
   that serves a drifted goal re-arms the drift before anything has
   tested it. One sentence, not a new stage.
4. **Recover per item. Act on evidence.** Classify against the real
   output and act:
   - **Progressing** (even if slow) → leave it; report it is alive and
     moving. Do not kill work that is making progress.
   - **Resumable** → resume it. Prefer a real resume over a restart when
     the mechanism supports one (a workflow resume reuses the cached
     prefix instead of redoing work).
   - **Dead but safe to redo** → restart it (subject to the autonomy
     policy below). Read from the evidence why it died, and fit the
     restart to that cause. If the same command fails identically each
     time, or the input itself is bad, a plain rerun only reproduces the
     failure, so change the input or the approach before restarting. If
     it hit a ceiling on turns, context or wall-clock time, restart it on
     a narrower slice of the work. If the cause sat outside the work, such
     as a network drop, a 5xx from a server, or a rate limit that has
     reset since, restart it exactly as it was. If the evidence points at
     no cause, rerun once and watch whether the failure comes back.

     Each item gets at most two retries. When the second one also fails,
     the item is abandoned: record it with its last evidence, and replan
     what remains so it no longer depends on that item.
   - **Rate-limited agent** (a subagent or workflow agent from step 1's
     list) → never drop it silently. First run the reset check and the
     live re-check under "After a usage limit lifts" (including its
     ask-the-operator fallback when no live reading exists). If the
     limit still holds, hand back with `/session-flow:handoff` instead of
     resuming. Otherwise read its partial work from the artifacts (its
     worktree, branch, commits, PR, files written), then resume it: a
     subagent through `SendMessage` to its id, a workflow agent through
     its workflow resume (the **Resumable** bullet), never a new
     workflow run. Do not spawn a replacement for either. When the id no
     longer resolves (step 2's gone-session case), restart from that
     trail, fitting the restart to the cause as in "Dead but safe to
     redo". Each resume or restart counts toward the two retries, and
     the side-effect gate applies to both.
   - **Unrecoverable** → surface it plainly; do not fake a recovery.
5. **Reconcile the main thread.** Restate where the primary task
   actually stood, grounded in a fresh read of any plan / checklist /
   task artifact backing it, not a prior turn's claim, and continue it.
6. **Report.** The step 2 snapshot is not reprinted; the report states the
   final state of any item or window a later step changed. Open the report with whatever needs the user: a gated kill or
   re-fire, or a question about the goal. Below it, one list sorts every
   item as still-running, recovered, restarted, abandoned, or lost /
   unrecoverable. Name every child process step 1 flagged as waiting on
   input, with its command line, and every `unknown` verdict; killing one
   stays behind the side-effect gate below. Work picked up from another agent's trail adds its
   verdict and the split between inherited and redone work (next
   section). Every rate-limited agent from step 1 appears with its
   partial-work evidence and its final action: resumed, restarted, or
   abandoned with its reason. A limit that still held is listed as
   handed back, with the reset it waits on, in the same report that
   precedes the stop.

## Picking up another agent's trail

Run this check when another session or agent did the work you are
resuming, after step 3 has tested the goal:

1. Open the artifact behind each status line the trail writes about
   itself ("tests pass", "done"): run the test command, read the
   branch, open the PR. Each line is confirmed or false; nothing rests
   on a line that is not confirmed.
2. Find the one row that matches the trail's confirmed end state. The
   trail gets that row's verdict and no other.

| Confirmed end state | Verdict | Action | Report entry |
|---|---|---|---|
| A change or recommendation is finished but nobody delivered it | **Ship the finished recommendation** | Deliver it | Taken over: the delivered item |
| A conclusion is waiting for someone to accept it | **Ratify** | Test it against today's evidence | Whether it holds, and each place it fails |
| Work stopped partway and still serves the goal | **Continue** | Resume from its last confirmed point | Taken over: the confirmed items; redone: any false ones, each with its reason |
| Work failed, or serves a goal that has since drifted | **Restart** | Start again from the goal | Why the trail was dropped |

The confirmed parts of the trail are where you start. Redo only what
step 1 found false or what the verdict calls for, so an item the trail
had already proved never appears among the redone items. The report
keeps taken-over and redone items in two lists, each redo with its
reason.

## Zone input (presence-gated, conservative)

Step 5 continues the main task in **this** session, and that is only right
when this session's context is still fit for the work. When the
`context-guard` plugin is enabled, look up this session's zone word with
its `mcp__context-guard__status` pull tool, or resolve it per its reader
contract, before continuing (the contract owns the snapshot
path, staleness rule, and bands. Read them there; this skill consumes
only the resulting word and inlines no band values). Never substitute
your own estimate of the remaining window for the instrument's reading.
Plugin not enabled, absent snapshot, or
`unknown` → judge from response quality alone, conservatively. A degraded
zone, or context-guard's evidence-degraded marker for this session, does
not stop the recovery (steps 1-4 are reads and evidence-gated actions
either way); it changes where the *continuation* goes. Route it with
`/session-flow:workflow continue`, whose router in
[`../workflow/context/continuation.md`](../workflow/context/continuation.md)
makes that choice.

## Active-verification protocol. Evidence before action

For any "is it stuck / check the monitor / poke it":

- **Read the real output first**. Monitor status, subagent
  transcript/output, task output, shell logs. Judge from the artifact,
  never from "it has been a while."
- **Progress-vs-elapsed is a suspicion-raiser only.** Slow relative to
  elapsed time tells you to look closer; it never by itself authorizes a
  kill. Confirm "dead" or "stuck" against the actual output.
- **When the evidence is ambiguous, treat the work as alive.** Killing
  live-but-slow work that was actually progressing is the failure mode to
  guard against.

## Autonomy policy. Resume freely, gate side effects

- **Auto-resume** safe, idempotent, read-only, or clearly incomplete
  work without asking. Recovery should not stall on confirmation for work
  that cannot double-fire. Keep going when a step needs no input, with
  status notes in the same message as the next action; never end on an
  offer to continue, a summary naming the next step without taking it, or
  a list of options that block nothing.
- **GATE** before RE-FIRING anything with external side effects, a push,
  a PR comment, a sent message, a deploy, a mutation, **and** before
  KILLING or RESTARTING off-thread work whose death you cannot prove from
  step 2. When the inspection cannot prove the action did NOT already
  land, or cannot prove the work is actually dead, stop and ask.
  Double-firing a side effect, or killing live work, is worse than
  pausing.

## After a usage limit lifts. GO, don't summarize

- If you are executing again, the block is already over: **continue the
  work**. Do not produce a summary and stop. Summarize-and-stall is the
  failure mode. Put status notes in the same message as the next action.
- A rate-limited subagent resumes through `SendMessage` to its id, and a
  workflow agent through its workflow resume, once the live re-check
  shows headroom (step 4's rate-limited path); do not spawn a
  replacement.
- The time-vs-reset check belongs to the **orchestration** case: when
  step 2 inspects a worker or subagent that is itself limited, compare the
  current time against the reset its limit message states, to decide
  whether that worker can proceed now. Run the bundled checker instead of
  doing this arithmetic yourself:

  ```shell
  python3 "${CLAUDE_PLUGIN_ROOT}/skills/keep-going/scripts/check-usage-limit-reset.py" "<limit message text>" --received "<ISO-8601 time the message appeared, with offset or Z>"
  ```

  Pass `--received` with the time the limit message appeared: the timestamp
  of the transcript entry that carries it, else the time you captured it. A
  message states only a clock time, so without `--received` a reset time
  already past on today's clock reads as passed even when the message meant
  tomorrow. When no time is known, omit the flag and treat exit `0` as
  provisional, like exit `1`.

  Exit `0` means the reset has passed, treat the worker as resumable now.
  Exit `1` means the limit is provisional until a live re-check of the
  current account confirms it (next bullet); only then hand back by invoking
  `/session-flow:handoff` via the Skill tool and stop. Exit `2` means the checker could not parse its input; read stderr
  first. `no reset clause found` means the message had none: say so plainly
  and ask the operator rather than guessing. `--received needs an offset or Z`
  means your own `--received` value was malformed: fix it and rerun. Exit `3` means the
  reset clause parsed but the IANA timezone could not be resolved (rare when
  the bundled `tzdata` under `scripts/vendor` is present); report the timezone
  failure rather than treating the message as unparsable. In a single
  interactive session, if you are running, the answer is already GO. A date-bearing
  form such as `resets Sep 8, 6pm (America/New_York)` is unparsed (exit `2`); never
  treat exit `2` as lifted.
- The limit **message text** (e.g. `resets 3:45pm`) is a capture bound to the
  account that emitted it. Two live readings of the *current* account count:
  the `/usage` view, which the operator relays because the model cannot open
  it, and the session's `rate_limits` windows, which this skill reads through
  rate-limit-guard's `mcp__rate-limit-guard__status` pull tool when the guard
  is installed and mods are on. For which fields the statusline `rate_limits`
  object carries and who receives it, see
  [statusline: Available data](https://code.claude.com/docs/en/statusline#available-data);
  the record below holds its as-of date and recheck trigger. A captured
  message never drives a still-blocked verdict by itself: re-check live
  before handing back. When no
  live reading is obtainable (mods off, the guard not installed, the
  tool's registration refused by policy, or a tool answer with no windows,
  `verdict: "unknown"`, as under API-key or enterprise auth), ask the
  operator which account is active and whether it has
  headroom, as in the exit `2` path. Never invent a window and never conclude
  still-blocked.
- **Name both accounts before reading the message against the live reading.**
  Read the active account's identity from `claude auth status` at resume,
  using whichever field in its output identifies the account. A field that
  only describes how the CLI is configured never makes an identity known:
  with no identifying field the state is unknown. The account at the time of the stop is the one the stop entry, the
  handoff or the operator recorded. Report both, each with its source, and one
  of three states:
  - **unchanged**: both identities are known and equal, so the captured
    message and the live reading describe one account and the limit may have
    lifted (apply the reset check above).
  - **changed**: both are known and differ, so the captured message belongs to
    the old account. Do not read it against the current one; take the current
    account's own live reading (or the operator's answer when none is
    obtainable, as above) and say the account changed.
  - **unknown**: either side is missing, unreadable (`claude auth status`
    fails or shows no identifying field) or ambiguous. Ask the
    operator which account is active and which one hit the limit; never infer
    a state, and say why the reading failed.

  Switching accounts or driving account rotation is not this skill's job.

  | Decision | Pointer | As of | Recheck trigger |
  |---|---|---|---|
  | A captured usage-limit message is account-bound. Still-blocked requires a live re-check of the current account, or the operator's answer when none is obtainable. The date-bearing `Sep 8, 6pm` form is unparsed (exit 2). | For the reset time a limit message carries, see [costs: When a developer asks about a limit](https://code.claude.com/docs/en/costs#when-a-developer-asks-about-a-limit). For what `/usage` shows a subscriber, see [costs: Using the `/usage` command](https://code.claude.com/docs/en/costs#using-the-/usage-command). For the `rate_limits` field, who receives it and when, see [statusline: Available data](https://code.claude.com/docs/en/statusline#available-data). For the parsed forms, see `check-usage-limit-reset.py` `RESET_RE` (no month token). For the account-identity reading, see [CLI reference: CLI commands](https://code.claude.com/docs/en/cli-reference#cli-commands) `claude auth status`. | 2026-10-18 | That costs section stops covering the reset time; `/usage` stops showing plan usage bars; the statusline page drops `rate_limits` or starts passing it to the model; `claude auth status` stops reporting an identifying field or changes its output; or `RESET_RE` starts matching a date-bearing form. |

## Still blocked (limit not yet reset). Hand back, don't busy-wait

While a limit still holds you cannot make progress in this session.
Compose with `/session-flow:handoff` to drop a resume artifact so nothing
is lost, then stop. Automatic wake-and-continue at the reset time is an
external scheduler's job, a desktop scheduled task or a cloud routine
launched to resume from that handoff, not this skill's; keep-going hands
back cleanly and stops. Reach this step only through the live re-check in
the reset bullet above.

## Nothing-off-thread case

If the inventory finds no off-thread work, say so (the snapshot's
off-thread field reads `none found`), run step 3's
goal-alignment check when a handoff backs the resume, then go straight to
step 5: reconcile the main thread from its real state and continue. The
interruption may have hit mid-turn on the main thread alone. Recovering
that is still the job.

## What this skill does NOT do

- **Does not choose a recovery from the interruption type.** A short
  limit, a weekly limit, or a crash all take the same recovery. The
  snapshot's cause line shows the evidence and is not used to pick a
  method. (Reading a stated reset time to gate a blocked worker does not
  change the recovery method either.)
- **Does not kill or restart live-but-slow work on a hunch.** Action
  follows real output, and kill/restart is gated like any side effect.
- **Does not build or arm its own scheduler.** Still-blocked work is
  handed back by invoking `/session-flow:handoff` via the Skill tool, not parked on a self-armed
  wakeup.
- **Does not trust remembered state.** Every status claim is grounded in
  a fresh read of the real artifact.

## Next

/session-flow:workflow continue

It routes how the recovered session carries on at the next phase boundary.

## Gotchas

- "Probably done" is one failure mode; "it has been a while, kill it" is
  the other. A resumable job that looks finished may have died at 90%; a
  side-effect that looks unsent may have landed just before the cutoff;
  live-but-slow work that looks hung may be one step from done. Read the
  artifact before you decide.
- After a limit lifts, the pull is to summarize and hand back. Resist it:
  if you are running, continue, and report at the end.
