---
description: "Executes an enforcement-surface audit's findings one at a time behind an explicit per-item human gate, down the rollback ladder: config-disable first, observe, delete last. The only skill in this plugin that changes the surface; it never scans or re-judges. Use when the user wants accepted audit findings carried out, a judged gate or hook retired, or one disabled and observed."
argument-hint: "[finding-id ...] [layer ...]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: implement
  summary: Execute accepted audit findings down the rollback ladder behind a per-item human gate
---

**Arguments.** `[finding-id ...] [layer ...]`. Default: every finding awaiting a decision, in the artifact's order

## Repository context. Gather first

Run this as its own Bash call, never combined with another command:

- Branch, `git symbolic-ref --quiet --short HEAD`

Treat a failure (detached checkout, no repository, no git) as an unresolved identity.

## Pre-computed context

- Today (UTC): !`date -u +%Y-%m-%d 2>/dev/null || echo "unknown (no date command)"`

## Purpose

Execute what an `overengineering:audit` run found, one finding at a time, with the operator deciding
each. This is the only skill that mutates the surface under scrutiny, and the per-item gate below is
what makes that safe.

Read `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` before executing anything: the rollback
ladder (§11), protected classes and their cap (§7), UNPROVEN triage (§8), ownership and out-of-repo
custody (§12), the verdict ladder (§6), and the scope boundary (§10). The artifact's shape, status
vocabulary, merge rules and durable judgment record are
`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`'s. Every bare `§N` here is a scrutiny-method
section. Cite both documents rather than paraphrasing either in a proposal.

## The per-item gate

**Nothing mutates without an explicit acceptance of that finding, from the operator, at the moment it
is presented.** Say so in the run's opening line, then hold it literally:

- **One finding, one acceptance.** Accepting A authorizes A's remediation and nothing else: not its
  neighbors, not the rest of its layer.
- **Blanket approval is not the gate.** "Approve everything", "do whatever the audit says", and a
  standing authorization from earlier in the session are declined, out loud, with an offer to walk
  the queue instead.
- **Silence is not acceptance.** An unanswered finding stays `OPEN`; it does not become `REJECTED`
  and is not carried on a later item's yes.
- **Acceptance covers the rung or act about to execute.** A yes at rung 1 of §11 authorizes the
  config-disable, not the deletion; rung 3 asks again after the window.
- **Change approval shows the exact change first.** The file and line, the config key and its new
  value, or the entry to be written, shown after the plan and approved before any write, then
  executed as shown and nothing adjacent.
- **No operator present means present and stop.** In a dispatched, scheduled or background run,
  present the queue and stop: no status transitions, nothing written. There is no unattended mode.

**Both gates are required.** Item acceptance authorizes working the finding and the act named at
that moment; change approval authorizes one exact edit. An earlier acceptance is not approval of the
edit that later falls out of it.

## Before anything: load the artifact

1. **Resolve the branch identity, then the home.** `HEAD` and a failed call are never an identity.
   Where the call fails, use a logical ref the environment supplies only after `audit`'s
   normalize-then-validate steps (strip a leading `refs/heads/`, `git check-ref-format --branch`,
   refuse `.` and `..` segments), and name its source. Otherwise stop, per "An unresolved branch
   identity is its own refusal". Compose the home per `findings-artifact.md` "Where it lives".
2. **No artifact: stop.** Say visibly that no findings artifact exists at the resolved home, name
   that home, and name the two producers: `overengineering:audit` for a walk of the enforcement
   surface and `overengineering:justify` for one artifact the operator points at. Do not scan, judge
   or remediate anything yourself; this skill has no evidence or verdict of its own.
3. **Refuse a mismatched `branch:`**, naming both; **refuse a `branch:` that is absent, empty or the
   literal `HEAD`**, naming which, without comparing; and **refuse an unrecognized `schema:`**, each
   with a visible message. `1` and `2` are recognized. On `schema: 2`, `mode`, `targets` and `Basis`
   are displayed with the finding and change no gating decision; a schema-1 row's missing `Basis`
   displays as `not recorded (schema 1)`. The artifact's frontmatter binds it to a branch; its
   directory does not.
4. **Read the evidence-availability assessment that leads the artifact; never recompute it.**
5. **A `Status` outside the closed vocabulary** is reported and that finding skipped.
6. **Surface a verdict that moved under a carried-forward judgment first, and never act on it.**
   Read the flag the recomputing producer wrote; never re-derive it. An `ACCEPTED` finding now `KEEP`,
   a `REJECTED` one now retirement-direction, or an `ACCEPTED` verdict whose authorized act changed
   (`DOWNGRADE` now `CONSOLIDATE`) means the evidence moved under the operator's decision. Re-confirm
   the act before anything proceeds.

## Arguments

Finding ids and layer names from the artifact's vocabulary narrow the queue to exactly those
findings. Anything else is a free-text hint that orders the queue, reported when it matches nothing.
No argument widens the queue or replaces the gate. Bare invocation presents every finding awaiting a
decision in the artifact's order; a queue too long for one sitting is said to be, and stopping
halfway is a normal end, since statuses persist.

## The queue

Present every finding in the artifact's order and dispose of each by its status. A finding in one of
the justification layers (`decision-records`, `documents`, `components`, `dependencies`, `source`)
has no rollback ladder here, and is presented and judged but never remediated: the rung-1-inapplicable
route below would turn it into a deletion. Display its evidence, verdict and the owner from that lane's boundary
table, say in one line that no rung is offered, and still take the operator's decision (`REJECTED`,
or `DELEGATED-EXTERNAL` where custody is upstream). Dispatch on `Layer`, never the `check` segment,
which cannot be read back off an id (`findings-artifact.md` "Finding ids").

| Status | What this run does with it |
|---|---|
| `OPEN` | Present the verdict, its evidence, its cost, and the proposed rung; ask for a decision |
| `ACCEPTED` | Authorized in an earlier run: re-confirm the rung about to execute, then continue |
| `REJECTED` · `REALIGNED` | Nothing. Report it as already decided; do not re-ask |
| `DELEGATED-EXTERNAL` | Report the delegation pointer and its state. Nothing local, ever |
| `ABLATION-PENDING` | Gate and execute the rung-1 disable, then move to `ABLATION-ACTIVE` |
| `ABLATION-ACTIVE` | Compare today against the recorded end date; before it, report the window as running and stop there |
| `ABLATION-CONCLUDED-RETIRE` | Rung 3, behind its own acceptance |
| `ABLATION-CONCLUDED-KEEP` | Confirm the mechanism is re-enabled, close as KEEP, and offer the durable judgment entry |

## Per accepted finding: the four movements

Interview, explore and research, plan, implement. Each composes a sibling skill via the Skill tool
when its plugin is installed and runs the inline fallback when not. Say which ran and record the
presence answer on the finding.

| Movement | Composition (presence-gated) | Inline fallback when absent |
|---|---|---|
| **Interview**: intent, constraints, what done means | `/planning:interview` | Ask the same questions inline as one small numbered set, recommendation first |
| **Explore**: what the mechanism touches, where it is wired, what depends on it | `/discovery:explore` | Read the artifact, its registration surface and call sites, and list the blast radius before proposing anything |
| **Research**: is the replacement the rediscovery names real and current | `/discovery:research` | Check its current official documentation and record the check with its date (§5) |
| **Plan**: rung, exact edit, reversal, observation window | `/planning:plan` | Write goal, rung, blast radius and reversal in the response; get it approved before any edit |
| **Implement** | `/implementation:implement` | Make the change against the approved plan, one rung at a time, stopping at the same gates |

Run only the movements the finding needs: a one-key config disable with a settled intent needs no
research pass. Record a skipped one with its reason ("Skipped research: the rediscovery names a
mechanism already in this repo"), never skip it wordlessly.

## Execution order. The rollback ladder

§11 governs, in order; record the rung reached on the finding:

1. **Config-disable**, wherever a kill switch exists. Check §11's trap: where "unset means enabled",
   make the off state explicit, and confirm the disable took effect.
2. **Observe** for the consumer's configured window, with **its end date written on the finding**
   and on a durable pointer, since the artifact can be gone before the date.
3. **Delete, with the rationale recorded** in the change description: the evidence, the observation
   result, and what re-adds it. Preserve the re-add surface where one exists.

**Withdrawal is a normal outcome.** A window showing the mechanism load-bearing ends at rung 1 with
it re-enabled and the finding closed as KEEP with the window's evidence. Say so when proposing the
ladder.

**When rung 1 is inapplicable** (nothing registered or wired to disable: a copy nothing reads, a
claim in a document, a lane nothing requires), record *"rung 1 inapplicable: `<reason>`"* and why
rung 2 gives no signal. A reversible non-rung remediation (correct a false claim, register the copy
that should be wired) is then a valid proposal under its own acceptance. Where deletion is the only
remaining act, the acceptance must name the deletion explicitly.

**CONSOLIDATE** removes the redundant copy once the survivor is named: disable, observe under the
survivor, delete where the copy is live; deletion named in the acceptance where it is inert.

## UNPROVEN findings. The ablation track

An UNPROVEN verdict does not authorize a disable. Route it to §8's track: take the head of the
audit's carry-cost ranking, propose one bounded batch an operator can attend to, name an owner per
item (§12), set one window with its end date, and record a durable pointer. Each item still passes
the per-item gate. Items below the batch wait for the next window. Protected and intentionally
dormant items (§7) never enter a batch.

## Protected findings

A `FLAG-FOR-HUMAN` finding is a question, not a task. Present the capped verdict it would otherwise
carry, the evidence in full, the protected class and the rule that matched, then stop and wait for
the operator's own call on that item, in their words. Never retire a protected mechanism on this
skill's reasoning, and never route it into an ablation batch to reach the same end. An operator
overturning the classification records that in the consumer's tracked configuration.

## Out-of-repo custody. Delegate, never patch locally

Where the audit's custody read placed the artifact upstream (organization policy, a managed or
synced copy, a shared workflow this repo only references, a forge control plane), §12 makes the
remediation a delegation: produce an upstream change request, an administrator issue, or written
instructions for the owner, carrying the evidence and proposed rung, and set `DELEGATED-EXTERNAL`
with its pointer. Never edit the out-of-repo surface in place or patch a managed copy locally; the
next sync reverts it.

## Statuses this skill writes

**Re-read the artifact from disk immediately before every `Status` write, and merge against that
copy**; another producer may have written during a long interview.

This skill is the only writer of `Status`, and writes one only as its outcome happens, never ahead
of the operator's yes: `ACCEPTED` on acceptance; `REJECTED` when the operator keeps the mechanism;
`REALIGNED` when the change has landed; `DELEGATED-EXTERNAL` with its pointer; the `ABLATION-*` states
as a batch moves through its window. A justification-layer row takes `REJECTED` like any other: it
records a judgment and mutates nothing outside the record. Leave every other field as the audit
computed it.

## The durable judgment record

**Offer** to persist a `REJECTED` or `ABLATION-CONCLUDED-KEEP` finding as a suppression entry in the
consuming repo's tracked `.claude/overengineering.md`:

- Show the exact entry before writing it, and write only on an explicit yes under the per-item gate.
- The `reason` is the operator's own words; ask for them rather than recycling audit prose.
- Write it to the team-tracked layer: a personal-layer entry does not suppress.
- Entry keys, the constituents-authoritative rule and the layering are
  `${CLAUDE_PLUGIN_ROOT}/reference/consumer-config.md`'s. A `REALIGNED` finding needs no entry.

## An unresolved branch identity is its own refusal

The branch-match check protects against executing one ref's findings against another ref's surface,
and `HEAD` compares equal to itself. Both unresolved states refuse, and neither reaches the
comparison:

- **This checkout has no branch identity** (the call failed and no logical ref was supplied). Stop
  before reading the artifact and say: *"Detached checkout, no logical ref supplied; no branch
  identity, so the artifact's branch cannot be verified and nothing will be executed."* No queue, no
  status transitions, nothing written.
- **The artifact carries no branch identity** (`branch:` absent, empty or `HEAD`). Refuse it by name,
  and say that `overengineering:audit` writes no artifact without an identity, so this one did not
  come from it. Do not repair the field or fall back to its directory.

Never fall back to `HEAD`, the commit sha, or the home's slug to make up either side.

## Next

`/verification:confirm`. The finding stays open until the landed change is verified.

## Gotchas

- **An accepted finding is not an accepted deletion.** Acceptance authorizes the rung on the table at
  that moment.
- **Disable the copy the runtime actually reads.** Where a guard exists in a local and a packaged
  form, confirm which one the live configuration registers first.
- **Do not touch what the finding is not about.** A formatting fix, a stale comment or an adjacent
  tidy in the same file is outside the acceptance given.
- **A finding you realigned vanishes from the next audit.** The re-run records it under closed since
  last run; that is the contract working.
- **Never argue a quality-enabling practice onto the ladder** (§10). Tests, review, type checking,
  the build, and the record-keeping that makes the evidence tiers readable are outside this method.
