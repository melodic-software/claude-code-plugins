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
  Added text is not a cut, except a word that flips an existing instruction (`not`, `never`, `no`,
  `only`, `except`, `unless` and their contractions) inserted into it; script changes are covered
  by tests (Q5, Q48).
- **Suite run** (`mode: suite`), **label run** (the `eval: run` label, advisory, posts no record),
  **compare run** (`mode: compare`, posts the eval-pair record on a PASS): the three modes of
  [`pr-run-plugin-evals.yml`](../../.github/workflows/pr-run-plugin-evals.yml) (Q62).

## When a run is required

- Only for a new case; a grader, prompt, fixture or scaffold change to a case; or a cut. Nothing
  else requires one (Q4).
- A skill `description` or `when_to_use` edit, additive included, runs that plugin's triggering
  and no-fire cases (Q7). An additive-only one merges before that run, which follows on the
  default branch as below; a reworded one is a cut and runs before merge (Q11).
- No run for a description-only case edit, an additive skill edit (added instructions can still
  lower adherence to the rest, so `select` lists its cases as affected but not run, Q8), a restated upstream fact swapped
  for a pointer to its source ([skills-and-agents.md](skills-and-agents.md), C3), or a repair that
  re-points a renamed reference that `/evals:validate` proves resolves (C2, Q6).
- A model release triggers nothing. When a decision rests on a new model, the cases that decision
  cites run under the budget below (Q15).
- No smoke set on every change and no scheduled suite (Q12).
- A new skill ships with at least one deterministic triggering case; a new gate or stop rule ships
  with a case that hits it (Q22).

## Which cases run

- The affected cases of the changed skills, in any plugin, and no others (Q8, Q30). For a cut to
  an agent body, the affected cases of each skill that dispatches that agent (Q61).
- `/evals:plugin-eval select <diff-base>` names them, with the agent-run count; its `cases:` line
  is the eval workflows' `cases` input, so one dispatch runs exactly that set (Q5). No known
  mapping drops an affected case. A plugin-wide file (`hooks/`, `.mcp.json`, `plugin.json`,
  settings) starts no run; `select` lists it for the author to judge (Q9).
- Never a whole suite (C1). A suite run always sets `case`, `cases` or `tag`. The label run runs every
  suite a PR touches, so do not add the `eval: run` label until it runs only the affected cases
  (Q42).
- A legacy `evals.json` set is not evidence. A cut whose skill has only one converts it to
  `case.yaml` cases, or adds a deterministic case, in the same PR (Q38, Q61).

## Where and on what

- In CI only, never on a local machine (Q3, Q7).
- A cut, or a grader, prompt, fixture or scaffold change, runs its affected deterministic cases in a
  compare run before merge, whose PASS releases the eval hold (Q7).
- A compare run's arms also carry the plugin's `context/**/*.md` under the markdown rules
  `select-plugins.mjs` applies to `skills/` and `agents/`; `plugin.json` and `probes/` stay refused
  (owner decision,
  [owner-decisions.md#L380](https://github.com/melodic-software/architecture/blob/05ddd704c535f4c99c3410e06e2e962056d3b2bd/docs/owner-decisions.md#L380)).
- A cut whose only covering cases are judged adds a deterministic case for the changed behavior in
  the same PR (Q45).
- Four kinds of PR merge before their run, once `/evals:validate` passes: one that adds or edits
  cases with deterministic graders only and changes no skill text, because compare mode refuses
  arms that do not differ (Q43, Q56); a cut whose changed behavior cannot be checked without a
  judge (Q45); one that adds or edits a script or a case scaffold and cuts no existing skill
  text, since compare mode never runs a script beside a credential (`select-plugins.mjs`; owner
  decision, melodic-software/architecture#208); and a skill rename, since compare mode refuses its
  manifest and probe edits and a renamed skill has no comparable base arm (owner decision,
  [owner-decisions.md#L380](https://github.com/melodic-software/architecture/blob/3534f80d3eea2c08a582d1899c2862af44880b64/docs/owner-decisions.md#L380)).
  Any other cut keeps its compare run before merge: split it from the script change. One suite run
  on the default branch, scoped to the affected cases, follows; a rename's run uses
  `credential: subscription` and `runs: 3`. For a judged case, the dispatching session posts the
  record by hand under [Graders](#graders).
- The session that merged the PR dispatches that run, states its cost first and watches it; it
  fixes or reverts a failing case. With no live session, the next session that takes up the PR's
  follow-up does (Q57).
- An eval-pair record names one head. A push before the hold releases needs a new compare run (Q58).
- Every run uses the maintenance API key and stops at its credit stop, except a compare run
  dispatched with `credential: subscription`: both its passes run on the maintenance subscription
  token, and only for a PR whose author is a human on the trusted-actor list; `compare-prepare`
  refuses any other, a listed bot included, since a bot's PR can start from public issue text. A
  suite run dispatched with `credential: subscription` also runs on that token, only on
  the default branch and only with `case`, `cases` or `tag` set; `run-eval-subscription` refuses
  any other. Each keeps the affected cases, the per-run ceiling (a list-price estimate, not a
  plan-usage cap), `--no-publish`, the kill switch and the `CLAUDE_EVALS_DISABLED` switch. No
  fallback token follows either: a limit stop ends the run. The label run and every other eval run
  use no subscription token (Q14, Q53, as amended by the owner decision "Eval runs on a
  subscription token, case pruning, and how #18356 lands", 2026-11-23, in
  [owner-decisions.md](https://github.com/melodic-software/architecture/blob/main/docs/owner-decisions.md),
  and extended to suite runs by
  [owner-decisions.md#L370](https://github.com/melodic-software/architecture/blob/9fecf3f103380aa38f9a7936c4209330f9ab4bcd/docs/owner-decisions.md#L370)).

## Budget

- Count cost in agent runs (cases × runs × arms). State the case list, the agent-run count and the
  list-price estimate in the PR before dispatch (Q11). `/evals:plugin-eval` prices a run before it
  spends; prices themselves are the [pricing page](https://platform.claude.com/docs/en/about-claude/pricing)'s.
- One dispatch per affected plugin per head, within the per-run ceiling the workflow's
  `cost-cap-usd` and `max-cost-usd` inputs enforce (Q11).
- Split an affected set that exceeds one run's ceiling into several dispatches by `cases` list; never
  drop affected cases to fit (Q36). Each passing dispatch posts a record that would release the
  eval hold, so a split PR's hold also carries a `reason=eval-split` line, which the release step
  does not lift ([loop-lane hold convention](../contracts/loop-lane/README.md)); the dispatching
  session removes `do-not-merge` once every dispatch has passed.
- Re-run only on a new head that changes affected files (Q11).

## Reading a result

- State the smallest change the run could detect beside its verdict: "no loss" means no loss larger
  than that floor (Q37). The floor is reported, not gating; a reviewer weighs it (Q49).
- A grader that fails in every base run cannot show a loss. Fix it before its "no loss" counts
  (Q25).
- A suite case passes only when its unscored with-arm graders (`arm: with-only`, a Skill call)
  also pass at the threshold: the score leaves them out to keep `Δ` comparable, so a score alone
  can pass a run that skipped the skill's own action (`summarize.mjs`).

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
