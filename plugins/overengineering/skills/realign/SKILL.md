---
description: "Execute an enforcement-surface audit's findings behind an explicit per-item human gate. Consumes the findings artifact `overengineering:audit` produced — it never scans or re-judges the surface itself — and for each finding the operator accepts drives interview → explore and research → plan → implement through presence-gated skill composition, executing every removal down the rollback ladder: config-disable first, observe for a window with a stated end date, delete last with a recorded rationale. Unproven items route to a bounded, time-boxed ablation batch; security-class items surface the capped verdict's evidence and wait for the human's own call; remediation owned by an upstream or a forge control plane becomes a delegation rather than a local patch. Use when: 'realign our enforcement surface', 'act on the audit findings', 'execute the overengineering findings', 'retire the automation we agreed to retire', 'disable this gate and observe it', 'start the ablation window', 'peel back these hooks', 'the audit says retire it, do it'. This is the only skill in this plugin that changes anything, and there is no blanket-approve path."
argument-hint: "[finding-id ...] [layer ...] — default: every finding awaiting a decision, in the artifact's order"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: implement
  summary: Execute accepted audit findings down the rollback ladder behind a per-item human gate
---

## Pre-computed context

- Branch: !`git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown (no checkout)"`
- Today (UTC): !`date -u +%Y-%m-%d 2>/dev/null || echo "unknown (no date command)"`

## Purpose

Execute what an `overengineering:audit` run found — one finding at a time, with the operator
deciding each one. This is the **only** mutating surface in this plugin, and the per-item gate below
is the entire reason it is safe to point at a surface nobody has reviewed in a year.

The method is **not restated here.** Read `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` before
executing anything: the rollback ladder (§11) that orders every removal, the protected classes and
their cap (§7), UNPROVEN triage and its bounded batches (§8), ownership and out-of-repo custody
(§12), the verdict ladder (§6) whose tokens the artifact carries, and the scope boundary (§10) that
puts tests, review, type checking, and the build outside this work. The artifact's shape, its status
vocabulary, its merge rules, and the durable judgment record belong to
`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`. Every bare `§N` in this skill is a section of
the scrutiny method, and a paraphrase of either document inside a proposal is a drift seed.

## The per-item gate

**Nothing mutates without an explicit acceptance of that finding, from the operator, at the moment
it is presented.** Say so in the run's opening line, then hold it literally:

- **One finding, one acceptance.** Accepting finding A authorizes A's remediation and nothing
  else — not its neighbours, not the rest of its layer, not the obvious next one.
- **Blanket approval is not the gate.** "Approve everything", "do whatever the audit says", and a
  standing authorization from earlier in the session are all declined, out loud, with an offer to
  walk the queue instead. A gate that a sentence can switch off was never a gate.
- **Silence is not acceptance.** An unanswered finding stays `OPEN`; it does not become `REJECTED`,
  and it is not carried on a later item's yes.
- **Acceptance is scoped to the rung about to execute.** A yes at rung 1 of §11 authorizes the
  config-disable, not the deletion three rungs later; rung 3 asks again, after the window.
- **Show the exact change before making it.** The file and the line, the config key and its new
  value, or the entry to be written — then execute what was shown, nothing adjacent.

## Before anything: load the artifact

1. **Resolve the artifact home** by running the whole rung order in
   `${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`. A hardcoded path reads where the audit never
   wrote, and that failure is indistinguishable from the audit never having run.
2. **No artifact → stop.** Report, visibly, that no findings artifact exists at the resolved home,
   name `overengineering:audit` as the skill that produces one, and name the home resolved so the
   operator can tell "never audited" from "resolved elsewhere". **Do not scan, judge, or remediate
   anything on your own** — this skill has no evidence and no verdict of its own, so an improvised
   pass would put a mutation behind a gate with nothing behind it.
3. **Refuse a mismatched `branch:`**, naming both, and **refuse an unrecognized `schema:`** with a
   visible message rather than guessing at the shape. The artifact's own frontmatter is what binds
   it to a branch; the directory it sits in is not evidence (the slug mapping is lossy).
4. **Read the evidence-availability assessment that leads the artifact, and never recompute it.** It
   changes what UNPROVEN means for every finding below it, and re-deriving it here would make a
   second record that can disagree with the first.
5. **A `Status` value outside the artifact's closed vocabulary** is reported and that finding is
   skipped — soft degradation, never a guess about what an unknown state meant.
6. **Surface a verdict that flipped direction under a carried-forward judgment before anything else,
   and never act on it.** An `ACCEPTED` finding now recomputed to `KEEP`, or a `REJECTED` one now
   recomputed to a retirement-direction verdict, means the evidence moved under a decision the
   operator already made. That is a question for them, not an instruction to this skill.

## Arguments

Parse `$ARGUMENTS`. **Finding ids**, and **layer names** from the artifact's layer vocabulary,
narrow the queue to exactly those findings. Anything else is a free-text hint that orders the queue
and is reported rather than dropped when it matches nothing. No argument widens the queue, and none
replaces the gate. Bare invocation presents every finding awaiting a decision, in the artifact's own
order; a queue too long for one sitting is said to be, not rushed — the statuses persist, so
stopping halfway is a normal end to a run.

## The queue

Present findings in the artifact's order and dispose of each by its current status:

| Status | What this run does with it |
|---|---|
| `OPEN` | Present the verdict, its evidence, its cost, and the proposed rung; ask for a decision |
| `ACCEPTED` | Remediation was authorized in an earlier run — re-confirm the rung about to execute, then continue |
| `REJECTED` · `REALIGNED` | Nothing. Report it as already decided; re-asking is the noise the judgment record exists to stop |
| `DELEGATED-EXTERNAL` | Report the delegation pointer and its state. Nothing local, ever |
| `ABLATION-PENDING` | Gate and execute the rung-1 disable, then move to `ABLATION-ACTIVE` |
| `ABLATION-ACTIVE` | Compare today against the recorded end date; before it, report the window as running and stop there |
| `ABLATION-CONCLUDED-RETIRE` | Rung 3, behind its own acceptance |
| `ABLATION-CONCLUDED-KEEP` | Confirm the mechanism is re-enabled, close as KEEP, and offer the durable judgment entry |

## Per accepted finding: the four movements

Interview → explore and research → plan → implement. Each composes a sibling skill **when its plugin
is installed** and runs the documented inline fallback when it is not. Check presence, take the
fallback, and **say which one ran** — a silent skip is indistinguishable from a step that was never
needed. Record the presence answer on the finding.

| Movement | Composition (presence-gated) | Inline fallback when absent |
|---|---|---|
| **Interview** — settle intent, constraints, and what "done" means for this item | `/planning:interview`, when the planning plugin is installed | Ask the same questions inline as one small numbered set, recommendation first. The questions are the substance; only the mechanics are lost |
| **Explore** — what the mechanism touches, where it is wired, what depends on it | `/discovery:explore`, when the discovery plugin is installed | Read the artifact, its registration surface, and its call sites directly, and list the blast radius in the response before proposing anything |
| **Research** — is the native or existing mechanism the rediscovery names real, and current | `/discovery:research`, when the discovery plugin is installed | Check the current official documentation of the proposed replacement yourself and record the check with its date (§5 requires the date, not the memory) |
| **Plan** — the rung, the exact edit, the reversal, the observation window | `/planning:plan`, when the planning plugin is installed | Write the plan in the response — goal, rung, blast radius, how it is reversed — and get it approved before any edit |
| **Implement** — make the change | `/implementation:implement`, when the implementation plugin is installed | Make the change directly against the approved plan, one rung at a time, stopping at the same gates |

Run the movements the finding actually needs — a one-key config disable with a settled intent needs
no research pass. "Skipped research: the rediscovery names a mechanism already in this repo" is a
judgment recorded; skipping it wordlessly is not.

## Execution order — the rollback ladder

§11 governs, in order, and the finding records the rung reached:

1. **Config-disable**, wherever a kill switch exists. Check §11's trap first: an "unset means
   enabled" fallback re-enables a mechanism that was disabled by removing a key, so make the off
   state explicit and confirm the disable took effect rather than assuming the edit was the effect.
2. **Observe** for the consumer's configured window, with **its end date written on the finding**. A
   window with no end date is an abandonment wearing an experiment's clothes, and the date belongs
   on a durable pointer too — the artifact can be gone before the date arrives.
3. **Delete, with the rationale recorded** in the change description: the evidence, the observation
   result, and what re-adds it. Preserve the re-add surface where one exists.

**Withdrawal is a normal outcome, not a failure.** A window showing the mechanism load-bearing ends
at rung 1 with it re-enabled and the finding closed as KEEP, carrying the evidence the window
produced. Say so when proposing the ladder — it is what makes rung 1 cheap to accept.

## UNPROVEN findings — the ablation track

An UNPROVEN verdict is not an authorization to disable. Route it to §8's track: take the head of the
carry-cost ranking the audit recorded, propose **one bounded batch** an operator can actually attend
to, name an owner per item (§12 — ownerless is not a terminal state), set one window with its end
date, and record a durable pointer so the batch survives the artifact. Each item still passes the
per-item gate individually. Items below the batch keep their ranking and wait for the next window —
dozens of concurrent windows destroy attribution and re-check nothing — and protected and
intentionally-dormant items (§7) never enter a batch at all.

## Protected findings

A `FLAG-FOR-HUMAN` finding is a question, not a task. Present the capped retirement-direction
verdict it would otherwise have carried, the evidence in full, the protected class that matched, and
the rule that matched it — then **stop and wait for the operator's own call**, on that item, in
their words. Never retire a protected mechanism on this skill's own reasoning, and never reach the
same end by routing it into an ablation batch. Where the operator overturns the classification, that
is their decision to record, and the consumer's tracked configuration is where it belongs.

## Out-of-repo custody — delegate, never patch locally

Where the audit's custody read placed the artifact upstream — organization-level policy, a managed
or synced copy, a shared workflow this repo only references, a forge control plane — §12 makes the
remediation a **delegation**. Produce the delegation artifact — an upstream change request, an
administrator issue, or written instructions handed to the owner, carrying the finding's evidence
and the proposed rung — and set the status to `DELEGATED-EXTERNAL` with its pointer. **Never edit
the out-of-repo surface in place and never patch a managed copy locally**: the next sync reverts the
patch and leaves a report claiming the work is done.

## Statuses this skill writes

This skill is the artifact's only writer of `Status`, and it writes one only as the outcome it names
actually happens — never ahead of the operator's yes. `ACCEPTED` on acceptance; `REJECTED` when the
operator judges the finding and keeps the mechanism; `REALIGNED` when the change has landed;
`DELEGATED-EXTERNAL` with its pointer; the `ABLATION-*` states as a batch moves through its window.
What each one means is the contract's, not this skill's. Leave every other field exactly as the
audit computed it — rewriting a verdict here puts this skill's opinion into the audit's record.

## The durable judgment record

A `REJECTED` finding and an `ABLATION-CONCLUDED-KEEP` one are judgments worth more than the
memory-tier artifact a branch switch or a reclaimed container loses. **Offer** to persist each as a
suppression entry in the consuming repo's tracked `.claude/overengineering.md` — offered, not taken:

- **Show the exact entry before writing it**, and write only on an explicit yes, under the same
  per-item gate that authorized the remediation.
- **The `reason` is the operator's own words.** Ask for them. Audit prose recycled into that field
  is not a stated reason, and an entry nobody can review is an entry nobody can retire.
- **The team-tracked layer, not a personal overlay** — a personal-layer entry does not suppress, so
  writing one there would leave the operator believing a judgment is in effect when it is not.
- Entry keys, the constituents-authoritative rule, and the layering are owned by
  `${CLAUDE_PLUGIN_ROOT}/reference/consumer-config.md`. A `REALIGNED` finding needs no entry: the
  mechanism is gone, so it cannot recur.

## Gotchas

- **An accepted finding is not an accepted deletion.** Acceptance authorizes the rung on the table
  at that moment; carrying it to rung 3 is how a reversible change becomes an irreversible one that
  nobody agreed to.
- **Disable the copy the runtime actually reads.** Where a guard exists in both a local and a
  packaged form, disabling the inert copy changes nothing and reports as done — confirm which one
  the live configuration registers first.
- **Do not touch what the finding is not about.** A formatting fix, a stale comment, or an obvious
  adjacent tidy inside the same file is outside the acceptance that was given.
- **A finding you realigned vanishes from the next audit.** Its artifact is gone, so the re-run
  records it under closed-since-last-run instead — the contract working, not a loss.
- **Never argue a quality-enabling practice onto the ladder** (§10). Tests, review, type checking,
  and the build are outside this method, and so is the record-keeping that makes the evidence tiers
  readable at all — retiring it would make the next audit weaker than this one.
