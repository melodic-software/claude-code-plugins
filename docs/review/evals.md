# Evals

When an eval runs, which cases run, and what the evidence must show. Each rule names the owner
decision behind it (a `Q` id from the 2026-11-22 eval-run-policy interview). How a run works is
the [`/evals:plugin-eval`](../../plugins/evals/skills/plugin-eval/SKILL.md) skill's to state;
statistics and grading are [`/evals:methodology`](../../plugins/evals/skills/methodology/SKILL.md)'s.

- Eval cases hold no raw session or product transcript:
  [rule](../../.claude/rules/eval-case-transcripts.md).

## Terms

- **Affected case**: a case whose prompt starts with the changed skill's `/plugin:skill`, whose tag
  equals the skill, whose grader checks a call to it, or whose own files changed. A case that only
  mentions the skill is not affected (Q30).
- **Cut**: any removal or rewording of instruction text in a skill's `SKILL.md`, its reference or
  action files, or an agent body, including a verbatim move into a file that loads on demand.
  Added text is not a cut; script changes are covered by tests (Q5, Q48).
- **Suite run** (`mode: suite`), **label run** (the `eval: run` label, advisory, posts no record),
  **compare run** (`mode: compare`, posts the eval-pair record on a PASS): the three modes of
  [`pr-run-plugin-evals.yml`](../../.github/workflows/pr-run-plugin-evals.yml) (Q62).

## When a run is required

- Only for a new case; a grader, prompt, fixture or scaffold change to a case; or a cut. Nothing
  else requires one (Q4).
- No run for a description-only case edit, an additive skill edit, or a repair that re-points a
  renamed reference that `/evals:validate` proves resolves (C2, Q6).
- A model release triggers nothing. When a decision rests on a new model, the cases that decision
  cites run under the budget below (Q15).
- No smoke set on every change and no scheduled suite (Q12).
- A new skill ships with at least one deterministic triggering case; a new gate or stop rule ships
  with a case that hits it (Q22).

## Which cases run

- The affected cases of the changed skills, in any plugin, and no others (Q8, Q30). For a cut to
  an agent body, the affected cases of each skill that dispatches that agent (Q61).
- Never a whole suite (C1).
- A legacy `evals.json` set is not evidence. A cut whose skill has only one converts it to
  `case.yaml` cases, or adds a deterministic case, in the same PR (Q38, Q61).

## Where and on what

- In CI only, never on a local machine (Q3, Q7).
- A cut, or a grader, prompt, fixture or scaffold change, runs its affected deterministic cases in a
  compare run before merge, whose PASS releases the eval hold (Q7).
- A cut whose only covering cases are judged adds a deterministic case for the changed behavior in
  the same PR. When the behavior cannot be checked without a judge, it merges under the next rule
  instead (Q45).
- A PR that adds or edits cases with deterministic graders only, and changes no skill text, merges
  once `/evals:validate` passes, because compare mode refuses arms that do not differ. One suite
  run on the default branch, scoped to those cases, follows (Q43, Q56).
- The session that merged the PR dispatches that run, states its cost first and watches it; it
  fixes or reverts a failing case. With no live session, the next session that takes up the PR's
  follow-up does (Q57).
- An eval-pair record names one head. A push before the hold releases needs a new compare run (Q58).
- Every run uses the maintenance API key and stops at its credit stop. No eval run uses a
  subscription token (Q14, Q53).

## Budget

- Count cost in agent runs (cases × runs × arms). State the case list, the agent-run count and the
  list-price estimate in the PR before dispatch (Q11). `/evals:plugin-eval` prices a run before it
  spends; prices themselves are the [pricing page](https://platform.claude.com/docs/en/about-claude/pricing)'s.
- One dispatch per affected plugin per head, within the per-run ceiling the workflow's
  `cost-cap-usd` and `max-cost-usd` inputs enforce (Q11).
- Split an affected set that exceeds one run's ceiling into several dispatches by case glob; never
  drop affected cases to fit (Q36).
- Re-run only on a new head that changes affected files (Q11).

## Reading a result

- State the smallest change the run could detect beside its verdict: "no loss" means no loss larger
  than that floor (Q37). The floor is reported, not gating; a reviewer weighs it (Q49).
- A grader that fails in every base run cannot show a loss. Fix it before its "no loss" counts
  (Q25).

## Graders

- Deterministic first: write a grader on the tool call wherever the behavior shows as one (Q16).
- A judged grader's verdict counts only after it agrees with the owner's labels on a few dozen
  calibration samples in the case's `samples/`; an agent drafts the samples for the owner to mark
  (Q39, Q50).
- When a judged case is the evidence, the session that dispatched the run posts the eval-pair
  record by hand after reading a VALID, no-loss result (Q16).

## Upkeep

- A PR that renames, moves or removes a skill updates the cases that name it; `/evals:validate`
  fails a dangling reference in CI (Q21, Q32).
- Coverage means a deterministic triggering case per skill, and a fire and a no-fire case per gate
  or stop rule. No percentage target and no case-count cap (Q23, Q24).

## The master switch

- The org variable `CLAUDE_EVALS_DISABLED` stops every eval path; an eval job runs only while it
  reads exactly `false` (Q52).
- A session may set it to `false` for a decided, costed run and back to `true` after (Q52, Q55).
