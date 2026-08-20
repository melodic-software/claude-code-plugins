# pstack-arena — omit the skill, absorb four ideas

Lane 3 of the cursor/plugins pstack port. Upstream: `pstack/skills/arena/SKILL.md` (MIT), clone
pinned at `60c641e4`.

This lane's terminal deliverable is a **decision**, not a skill. The plan is recorded to the same
standard as the two lanes that shipped code, because the omission is the expensive part: a later
reader needs to see that `arena` was read closely and declined, not that it was skipped.

## Brief

### TLDR

Do not ship a general fan-out-and-judge skill. Fold four of `arena`'s ideas into the two
competitions that already exist (`architecture:improve` Design-It-Twice, `naming:name-it-better
tournament`) and into `prototype`'s shared discipline. Record the omission argument and its two
honest costs in `docs/upstream/cursor-pstack.md`.

### Goal

Upstream's `arena` runs N candidate solutions for an arbitrary task in parallel, judges them against
a rubric, and grafts the winner. The question this lane answers is whether that runner earns an
always-listed skill slot here.

It does not, and the reason is the Rule of Three. The full argument lives in
[`docs/upstream/cursor-pstack.md`](../../upstream/cursor-pstack.md#why-arena-ships-no-skill) and is
not restated here; the load-bearing fact is that this marketplace has **two** candidate-competition
sites, not three, and they disagree about nearly everything a shared runner would have to fix.

### Process note

This lane inverted the order used on lanes 1 and 2. Both of those recommended first and read the
incumbents second, and an adversarial `/planning:audit-answers` pass overturned the majority of the
answers both times. Here the incumbent survey ran **before** any recommendation was formed, and the
lane's file-level factual claims held under audit. The one that did not was in the *brief*, not the
recommendation: it asserted a design-it-twice branch in `planning:design` that does not exist.

## Constraints

1. **No new skill, and no new plugin.** The listing budget is already measured at 14× over the
   8,000-character description budget (ADR 0016). Every extra skill is a permanently-paid context
   line, and `arena` has no trigger vocabulary of its own — every phrase it would claim already
   routes to a domain incumbent.

2. **Absorbs land in the SSOT file, never in a second place.** `discipline:reuse-or-replace` forbids
   leaving the established way in place and quietly adding a divergent way alongside it. For
   prototype that means `context/discipline.md`, which `explore-directions` step 6 already defers to
   ("per the shared discipline"), not `SKILL.md`.

3. **No new evidence ladder, no new judging vocabulary.** Same constraint lane 2 operated under. The
   absorbs change what an existing competition *records*; none of them adds a scale.

4. **Reuse existing field names.** The rejected-alternatives field takes `rejected-reason`, the name
   the durable candidate artifact already carries, so one vocabulary covers both.

5. **The rejected-shapes part is fenced from fresh-eyes dispatch.** `PLUGIN-PHILOSOPHY.md:716` — the
   delegation contract hands a reviewer the artifact and not the story. Authoring rationale that
   travels into a fresh context re-imports the bias the fresh context exists to remove.

6. **Upstream's mechanics are adapted, not copied.** Two would have needed changing had the skill
   shipped, and neither drove the omission: `isolation: worktree` (rejected three times here with
   recorded reasoning) and the unconditional different-model-family judge (every cross-vendor site
   here is presence-gated with a named fallback).

## Acceptance criteria

- [x] AC1 — No new skill, agent, command, or plugin directory is created by this lane.
- [x] AC2 — `interface-design.md`'s return schema has a sixth part, **rejected shapes**, using the
      field name `rejected-reason`.
- [x] AC3 — That sixth part carries an explicit fence forbidding it from travelling into a
      fresh-eyes dispatch, with the condition that would tighten it (adding an independent judge).
- [x] AC4 — `interface-design.md` step 3 distinguishes convergence-anyway (signal),
      shape-divergence (designed null result), and assumption-divergence (re-frame trigger).
- [x] AC5 — A proposed hybrid carries a graft record naming what was taken and what was left
      behind with its reason.
- [x] AC6 — `actions/deepening.md`'s durable candidate schema carries a matching `graft-record:`
      field, so the ledger survives the conversation.
- [x] AC7 — `architecture`'s evals no longer pin the five-part schema, and cover the spread read
      and the graft record.
- [x] AC8 — `prototype/context/discipline.md` asks for the losing directions and their reasons, and
      for the graft attribution when the verdict is a hybrid.
- [x] AC9 — `prototype` rule 6 no longer reads as winner-only.
- [x] AC10 — `naming`'s `tournament` mode requires the scoring criteria to be settled and written
      down before the candidate pool returns, without making them secret.
- [x] AC11 — `naming`'s "does not copy or invent criteria" rule is preserved and reasserted for the
      mid-bracket case.
- [x] AC12 — `naming`'s evals cover the pre-commitment.
- [x] AC13 — `docs/upstream/cursor-pstack.md` carries an `arena` attribution row and an omission
      argument that (a) leads with the Rule of Three, (b) states the two costs plainly, and
      (c) names a recheck trigger pointing at `workflows/` rather than at a skill.
- [x] AC14 — Version bumps and CHANGELOG entries for all three touched plugins.

## Phases

- [x] **Phase 1 — Survey.** Read every candidate-competition site before forming a recommendation.
      Findings recorded in `.work/pstack-arena/interview-checklist.md`.
- [x] **Phase 2 — Round 1 (D1–D5).** Verdict and four landing sites.
- [x] **Phase 3 — `/planning:audit-answers`.** Overturned 4 of 5 challenged answers: re-argue the
      omission around the Rule of Three rather than the routing collision, demote the worktree and
      cross-vendor objections to adaptation notes, drop the circular "already rejected by name"
      reason, and flag `architecture`'s evals as the schema pin the plan had not mentioned.
- [x] **Phase 4 — Absorb into `architecture`.** AC2–AC7.
- [x] **Phase 5 — Absorb into `prototype`.** AC8–AC9.
- [x] **Phase 6 — Absorb into `naming`.** AC10–AC12.
- [x] **Phase 7 — Provenance and release.** AC13–AC14, then gates.

## What omitting costs

Carried here as well as in the provenance file, because a plan that only records what was built is
not a plan a later reader can argue with:

1. A user whose task is not a name, an interface, or a UI layout has no general fan-out-and-pick
   runner — only `session-flow:orchestrate`'s posture, `boris`'s pattern vocabulary, and the
   `Workflow` tool.
2. The fleet has no comparative judgment at all. Every judging site surveyed verifies *one* artifact
   against a standard; `naming`'s tournament is the sole exception and is locked to names. The
   absorbs improve how the two existing competitions record their outcome. They do not give the
   fleet a way to choose between rival solutions in general.

**Recheck trigger:** a second real consumer asks for arbitrary-task fan-out. Evaluate the native
`workflows/` slot then — deterministic control flow over subagents is what it is for — not a skill.
