# invocation-mode-doctrine — PLAN

Lane 8 of the AI Hero course steering chain
([#2910](https://github.com/melodic-software/claude-code-plugins/issues/2910); chain contract:
`docs/topics/pocock-course-lanes/PLAN.md` on branch `claude/plan-mode-discussion-55kszx`, steering
addendum `docs/upstream/aihero-steering-lanes.md`). Interview ledger:
`.work/invocation-mode-doctrine/interview-checklist.md` (8/8 answered, register gate clean).

## Brief

### TLDR

Adopt an evidence-driven invocation-mode rubric for the skill fleet — **model-invoked by default**
(`disable-model-invocation: false`), with three named exception classes taking `true` — homed in
exactly one place (`docs/conventions/invocation-mode/README.md` + convention-registry row), with
the ADR 0005-bounded fleet re-grade executed in-lane over the 10 non-setup `true` skills and
enforcement filed as follow-on work items.

### Goal

Every steering-lesson claim about skill invocation (lessons 3, 4-invocation-half, 5) ends in a
recorded decision: the rubric written and homed, the setup convention's documentation status
settled, the 17 missing-key skills decided, the router pattern given a verdict, the
invocation-reach invariant dispositioned against current official docs, and the fleet re-grade
question-bounded per ADR 0005.

### Constraints

- Lane discusses and decides; plugin changes are filed as work items, never made in-lane
  (chain contract). Docs-tier artifacts (conventions doc, registry row, STEERING/SSOT updates)
  land in-lane on `claude/pocock-steering-course-00zkvd`.
- ADR 0005 binds the re-grade: rubric-first, question-bounded — never an unbounded 211-skill
  sweep. The bounding question is fixed by Q7 (below); the 137 default-conformant skills get no
  sweep.
- Decision rows accumulate in `docs/upstream/aihero-steering-lanes.md`; lane 6 (#2904)
  harvests them into `docs/upstream/aihero-course.md` later — that file must not be created on
  this branch.
- Cross-skill invocation *phrasing* stays lane 6's candidate (#2904); this lane owns invocation
  *doctrine* only.

### Acceptance criteria

- [x] Rubric doc exists at `docs/conventions/invocation-mode/README.md`: default posture,
      exception classes, evidence axes, router verdict, 10-row grade table.
- [x] Convention-registry row added in `docs/PLUGIN-PHILOSOPHY.md`; one-line cross-references
      from its setup contract and Instruction economy sections.
- [x] Lane 8 decision rows (8 rows, lessons 3/4/5) recorded in STEERING.md with lane status.
- [x] SSOT (`docs/upstream/mattpocock-skills.md`) gap-3 verdict cells dispositioned; the
      invocation-reach tracked strand records CONFIRMED (docs-verified 2026-08-17), retires the
      upstream-release trigger, keeps the audit-side trigger.
- [x] Follow-on work items filed:
      [#2968](https://github.com/melodic-software/claude-code-plugins/issues/2968) (explicit
      `disable-model-invocation: false` on the 17 missing-key skills + `skill-quality:check`
      criterion requiring the key + `playbooks:skill-authoring` cross-link) and
      [#2969](https://github.com/melodic-software/claude-code-plugins/issues/2969)
      (`planning:questionnaire` flip to model-invoked — the one re-grade flip).
- [ ] #2910 closed with a summary; all artifacts committed and pushed on
      `claude/pocock-steering-course-00zkvd`.

### Decisions (interview register, 2026-08-17)

- **Q1 — default posture:** model-invoked default (`disable-model-invocation: false`); exception
  classes taking `true`: (i) side-effect/manual-timing workflows, (ii) setup skills (per the
  PLUGIN-PHILOSOPHY setup contract), (iii) maintainer-only skills. Evidence: a `true` skill is
  model-invisible everywhere (docs-verified); upstream issue mattpocock/skills#693 (desktop/web
  drop user-invoked skills from the listing); cloud sessions never load user scope; multi-repo
  discoverability; listing budget manageable via documented knobs
  (`skillListingBudgetFraction`, `skillListingMaxDescChars`, `skillOverrides: "name-only"`).
- **Q2 — home:** `docs/conventions/invocation-mode/README.md` + registry row; cross-links from
  PLUGIN-PHILOSOPHY (setup contract, Instruction economy), `playbooks:skill-authoring` (filed),
  and the #2962 design (comment).
- **Q3 — 17 missing keys:** normalize to explicit `false` + enforce via a new
  `skill-quality:check` criterion; one filed follow-on.
- **Q4 — setup convention:** already documented (PLUGIN-PHILOSOPHY "Setup is explicit and
  repeatable", landed `967db56c` before #2910 was filed); rubric class (ii) cross-references it.
- **Q5 — invocation-reach strand:** CONFIRMED against current official docs (2026-08-17);
  retire the upstream-release trigger, keep the audit-side trigger; the rubric owns the
  cross-skill-reach axis.
- **Q6 — router pattern:** REJECT the model-side router with reason (under the model-invoked
  default the always-present listing is the router; the `true` set is deliberately
  model-invisible). Human-side answer: `docs/SKILL-CHEAT-SHEET.md` + `claude-ops:inventory`.
  Domain-scoped composition routers (`discipline:sweep-all` precedent) remain an admitted,
  distinct pattern.
- **Q7 — re-grade bounding:** one question — do the 10 non-setup `true` skills fall into a
  rubric exception class? Graded in-lane; only flips filed. Result: 9 KEEP, 1 FLIP
  (`planning:questionnaire`).
- **Q8 — lesson decision rows:** 8-row table confirmed as drafted (recorded in STEERING.md).

### Captured assumptions

- The fleet measurement of 2026-08-17 (211 top-level skills = 137 `false` / 17 missing key /
  57 `true`, of which 47 `*:setup` + 10 non-setup) is current for this lane's grade.
- No consumer automation invokes a `disable-model-invocation: true` skill from another skill
  (zero live instances found at audit time; the audit-side strand trigger guards regressions).

### Out-of-scope

- Implementing any plugin change (frontmatter edits, check criterion, skill cross-links) — filed
  as work items.
- Re-grading the 137 default-conformant skills or sampling them (ADR 0005).
- Cross-skill invocation phrasing (lane 6, #2904) and `aihero-course.md` creation (lane 6).

### Deferred questions

None — all 8 register rows answered; no deferred or blocked rows.

## Plan

(Empty — this lane files implementation as work items; no `/planning:plan` phase.)
