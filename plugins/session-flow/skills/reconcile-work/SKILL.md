---
name: reconcile-work
description: "Retire finished off-thread work and reconcile this session's task ledger with reality — the prune-and-reconcile counterpart to keep-going's resume. Inventory the off-thread work this session spawned (background tasks, shells, monitors, scheduled jobs, subagents — open-ended), inspect each item's REAL state, retire the genuinely finished, and close the task-ledger items whose work is proven done; also report the read-only liveness of sibling sessions in this project (mtime + coarse tail, never deep-parsing). Auto-settles the provably-finished; GATES any kill of still-running work. Use when: 'reconcile the session', 'retire finished work', 'square up the task ledger', 'is anything still running that should be retired', 'close out finished tasks', 'prune done work', 'reconcile the ledger'. Boundary: 'is it stuck / pick it back up' is /session-flow:keep-going (resume); a read-only 'where do we stand' glance is /session-flow:orient; making git/PR work durable before shutdown is /session-flow:clean-stop. Fixes this session only; sibling sessions are report-only."
user-invocable: true
disable-model-invocation: false
---

# Reconcile work

## Purpose

As a session winds down — or once a batch of background work has
finished — two things drift out of sync with reality: **off-thread work**
that has completed but is still tracked as if it were running, and the
**task ledger**, which still shows as open work that is actually done. This
skill reconciles both against their real state: it inventories the
off-thread work this session spawned, inspects each item's actual output,
**retires** the ones genuinely finished, and squares this session's task
ledger with what actually happened. It also reports the liveness of sibling
sessions in the same project — read-only, because it cannot control them.

Where `/session-flow:keep-going` *resumes* work after an interruption — "is
it stuck, pick it back up" — this skill *retires* finished work and
reconciles the ledger — "is anything still running that should be retired,
and does the ledger match reality?" Same inventory-and-inspect machinery,
opposite telos: keep-going continues the work; this closes the books on the
part that is done.

## Boundaries — pick the right sibling

- **`/session-flow:keep-going`** — resumes and continues off-thread work
  after an interruption, and judges whether slow-looking work is stuck. This
  skill does the reverse end of the same lifecycle: it retires what has
  *finished* and reconciles the ledger. "Is it stuck / pick it back up" is
  keep-going; "is anything still running that should be retired" is this.
- **`/session-flow:orient`** — a read-only "where do we stand" briefing that
  reports off-thread work *at a glance*. This skill inspects that work's real
  state and mutates the ledger to match; orient writes nothing.
- **`/session-flow:clean-stop`** — makes git/PR/issue work durable and linked
  on the remote before the machine goes away. This skill reconciles the
  in-session task ledger and off-thread-work tracking; it touches no git
  state and pushes nothing.
- **`/session-flow:running-retro`** — observes the session and routes
  learnings, mutating nothing but a ledger of findings. This skill acts on
  the task ledger and the off-thread work itself.

## Steps

1. **Inventory off-thread work.** Enumerate the off-thread work this session
   spawned, per the kinds in
   [`${CLAUDE_PLUGIN_ROOT}/reference/off-thread-work.md`](${CLAUDE_PLUGIN_ROOT}/reference/off-thread-work.md)
   — an open-ended set (background tasks, shells, monitors, scheduled jobs,
   dynamic workflows, subagents), not a fixed catalogue.
2. **Inspect real state.** Read each item's actual output per that same
   doc's inspect-real-state invariant — never assume finished or dead. When
   the judgement is "finished vs still-progressing" for slow-looking work,
   apply `keep-going`'s richer **Active-verification protocol**
   ([`${CLAUDE_PLUGIN_ROOT}/skills/keep-going/SKILL.md`](${CLAUDE_PLUGIN_ROOT}/skills/keep-going/SKILL.md)):
   progress-vs-elapsed only raises suspicion, and ambiguous evidence means
   treat the work as alive.
3. **Retire the finished + reconcile the ledger.** Read this session's task
   ledger, then converge it on reality:
   - **Off-thread work proven finished** → retire it: clear it from tracking
     so it no longer shows as running.
   - **A task whose work is proven complete** → close it. Closing is
     evidence-gated (see the autonomy policy): a task is closed only when
     step 2 proved its work done, never on a hunch.
   - **Work still running** → leave it tracked and running; a *kill* is gated
     (see the autonomy policy), never a side effect of tidying.
   Reconcile **this session's own** ledger only. A spawned subagent owns an
   internal task list the parent cannot see — do not attempt to reconcile it.
4. **Sibling-session liveness — read-only inventory.** Report, but do not
   touch, other sessions in this project. Resolve the project's session-data
   directory per the retro skill's "Paths"
   ([`${CLAUDE_PLUGIN_ROOT}/skills/retro/SKILL.md`](${CLAUDE_PLUGIN_ROOT}/skills/retro/SKILL.md)),
   then enumerate the sibling transcript files there and judge liveness from
   **file mtime** (recently written ⇒ likely live) plus a **coarse tail read**
   for a one-line sense of what each is doing. Do **not** deep-parse the
   JSONL — its internal shape is officially unstable across releases, so
   anything past mtime and a shallow tail is drift-risk. These sessions are
   visible but not controllable: report their liveness; retire nothing.
5. **Report.** One list: what was retired / closed, what is still running
   (with any gated kill surfaced as a question, not an action), and the
   sibling-session liveness inventory marked report-only.

## Autonomy policy — auto-settle the finished, gate the kill

- **Auto-settle without asking.** Closing a proven-done task and clearing
  finished off-thread work from tracking is low-blast-radius bookkeeping and
  the whole point of the invocation — do it. The safety is in the evidence:
  "done" comes from step 2's real-state inspection, never assumed. A task
  closed while its work is still running is the exact failure this skill must
  not cause — the mirror of keep-going's "never kill what you cannot prove is
  dead."
- **GATE any kill.** Stopping or killing still-running off-thread work — an
  agent, a shell, a monitor, a scheduled job — is irreversible and can
  destroy live-but-slow progress. Do it only when step 2 PROVED the work is
  not still progressing; when that cannot be proven, do not kill — surface it
  as a question in the report. This gate is this skill's own; it is not
  shared with the sibling inventory skills, whose blast radii differ.

## Nothing-to-reconcile case

If the ledger already matches reality and no off-thread work has finished,
say so and stop. A session whose books are already square is a valid, common
outcome — do not manufacture retirements or ledger edits to look thorough.

## What this skill does NOT do

- **Does not resume or continue the work** — retiring the finished is the
  opposite of resuming; recovery is `/session-flow:keep-going`.
- **Does not make git or remote state durable** — no commits, pushes, PRs, or
  issues; that is `/session-flow:clean-stop`.
- **Does not prescribe the next stage** — that is `/session-flow:workflow`.
- **Does not fix sibling sessions** — their liveness is reported read-only;
  harness control reaches only this session's own work.
- **Does not read a subagent's internal task list** — it reconciles only this
  session's own ledger.
- **Does not enumerate MCP / browser / playwright tool state.** Cut from V1:
  no generic tool-state enumeration surface exists, and closing user-owned
  state (a browser tab) would be destructive-against-user. Deferred with a
  trigger — revisit when a generic tool-state surface appears in the harness,
  or a per-tool seam convention is established for it.
- **Does not deep-parse transcripts** — sibling-session liveness is mtime plus
  a coarse tail read only; the JSONL format is officially unstable.

## Gotchas

- **Closing a task is evidence-gated, exactly like a kill.** The pull is to
  close everything that *looks* done to make the ledger tidy; a task whose
  work is still running must stay open. Prove "done" from the real artifact
  first.
- **mtime is a liveness heuristic, not proof.** A recently-touched sibling
  transcript is *likely* live; a stale one is *likely* done. Report it as a
  heuristic, and never escalate a sibling reading into an action — you cannot
  control that session regardless.
- **Sibling sessions are visible but not yours.** The filesystem shows every
  session's transcript; that is visibility, not control. Retire only what this
  session spawned.
- **Never deep-parse the sibling JSONL.** mtime and a shallow tail are stable
  to read; the record's internal structure is officially warned to change
  across releases. Staying shallow keeps this inventory from breaking on an
  update.
