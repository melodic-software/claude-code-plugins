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
  by tests (Q5, Q48). An edit inside a skill's `## Next`, `## Related` or `## See also` section is
  not a cut: those sections name other skills for the person and change no tool call (owner,
  2026-11-24, after #18922; Q2212). Nor is renaming a routing heading (Boundaries, Scope boundary,
  Siblings, Routing, Handoff, Composition, Integration, Workflow position, What this skill does not
  do) to another of those names or to Next or Related (Q2212).
- **Suite run** (`mode: suite`), **label run** (the `eval: run` label, advisory, posts no record),
  **compare run** (`mode: compare`, posts the eval-pair record on a PASS): the three modes of
  [`pr-run-plugin-evals.yml`](../../.github/workflows/pr-run-plugin-evals.yml) (Q62).

## When a run is required

- Only for a new case; a grader, prompt, fixture or scaffold change to a case; or a cut. Nothing
  else requires one (Q4).
- A skill `description` or `when_to_use` edit, additive included, runs that plugin's triggering
  and no-fire cases (Q7). An additive-only one merges before that run, which follows on the
  default branch as below; a reworded one is a cut and runs before merge (Q11).
- Except a routing-only `description` or `when_to_use` edit, which runs nothing: with its routing
  clauses removed (a `Not for <case>: /plugin:skill`, `Skip when ... /plugin:skill` or
  `prefer /plugin:skill` clause, added, removed or reworded), every skill token treated as one
  (`plugin:skill` to `/plugin:skill`, or a renamed skill), and decided-term swaps (next rule)
  removed, the old and new text are equal. `select` lists the skill under `no-run-exempt:` with
  that reason (owner, 2026-11-25, Q2212).
- A decided-term swap or a comment-line deletion runs nothing, wherever `select` looks. A hunk is
  not a cut when it only swaps a term for the word [`docs/glossary.md`](../glossary.md) "Rejected
  terms" decided (or that word's last word, so `--lane` becomes `--area` for **focus area**), in
  either number, so that old and new are byte-identical once each swap is replaced, or only
  deletes lines a comment fills in a code, YAML or shell file (`#` for YAML, shell and Python,
  `//` and `/* */` for JS and TS; code before or after the comment disqualifies the line, and
  markdown is excluded because an HTML comment can carry instructions a model reads; so is a
  file whose base opens a heredoc, YAML block scalar, or triple-quoted or backtick string,
  where a comment-shaped line can be content).
  That holds for a skill body, reference or agent hunk, a frontmatter value such as
  `argument-hint` or `metadata.summary`, an eval case's prompt, `case.yaml`, grader, scaffold,
  fixture or sample, and a renamed file whose path and content differ only by such changes. A
  hunk with any other change keeps the rules above (owner, 2026-11-25, Q2212; comment deletions
  per ADR 0110).
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
- Five kinds of PR merge before their run, once `/evals:validate` passes: one that adds or edits
  cases with deterministic graders only and changes no skill text, because compare mode refuses
  arms that do not differ (Q43, Q56); a cut whose changed behavior cannot be checked without a
  judge (Q45); one that adds or edits a script or a case scaffold and cuts no existing skill
  text, since compare mode never runs a script beside a credential (`select-plugins.mjs`; owner
  decision, melodic-software/architecture#208); a skill rename, since compare mode refuses its
  manifest and probe edits and a renamed skill has no comparable base arm (owner decision,
  [owner-decisions.md#L380](https://github.com/melodic-software/architecture/blob/3534f80d3eea2c08a582d1899c2862af44880b64/docs/owner-decisions.md#L380));
  and one whose compare run cannot start, because the org API key is off or compare mode refuses
  the PR, where a FAIL of the run that follows reverts it (owner decision,
  [owner-decisions.md#L400](https://github.com/melodic-software/architecture/blob/5e9bdfd176c86f3ce17d0659b4121fdcb0bc6c04/docs/owner-decisions.md#L400)).
  Any other cut keeps its compare run before merge. One suite run
  on the default branch, scoped to the affected cases, follows; a rename's run uses `runs: 3`.
  For a judged case, the dispatching session posts the
  record by hand under [Graders](#graders).
- Only the compare run's own record that it cannot start counts. A run that passes its
  dispatcher, input and head checks and then finds `compare-arms.sh` refusing the PR
  (`compare-refused`) runs no arm and succeeds its `Compare Cannot Start: compare-refused` job.
  pr-merge's release step lifts the eval hold only when, for every plugin whose skill, agent or
  context text the PR changes (or, when it changes none, every plugin it changes), the newest compare run at the current head since the label was last
  added that names that plugin as its target is such a run, read back under the same checks as a
  compare record; a refusal for one plugin never lifts a hold over another plugin's cut. It comments
  `<!-- eval-hold-released head=<sha> cannot-start=compare-refused run=<run ids> -->`. A missing
  record alone keeps the hold, and so do a PR file list that does not read in full and, for a
  plugin, an older run at that head since the label that failed its `Compare Verdict` (a LOSS or
  VOID), is still going, or was re-run
  ([`release-eval-hold.mjs`](../../.github/scripts/pr-merge/release-eval-hold.mjs)).
- The session that merged the PR dispatches that run, states its cost first and watches it; it
  fixes or reverts a failing case. With no live session, the next session that takes up the PR's
  follow-up does (Q57). The merged PRs that owe their run are those whose comments contain the
  text `cannot-start=compare-refused`; read comment bodies for it, since GitHub search splits the
  marker into words and matches far more.
- An eval-pair record names one head. A push before the hold releases needs a new compare run (Q58).
- Every eval run reads only the `EVALS` role's secrets, `EVALS_CLAUDE_API_KEY` and
  `EVALS_CLAUDE_CODE_OAUTH_TOKEN`, never another role's and never the fallback token. A dispatched
  run spends the API key's credit first and moves to the subscription token when the key stops
  (unassigned, empty, or at its credit stop), with no input to choose. A compare run moves both its
  passes only for a PR whose author is a human on the trusted-actor list; for any other, a listed
  bot included (a bot's PR can start from public issue text), `compare-prepare` passes no token and
  the arms stay on the key. A suite run moves only on the default branch and only with `case`,
  `cases` or `tag` set; `run-eval-subscription` refuses any other. Each keeps the affected cases,
  the per-run ceiling (a list-price estimate, not a plan-usage cap), `--no-publish`, the kill switch
  and the `CLAUDE_EVALS_DISABLED` switch. A limit stop on the token ends the run. When both halves
  are unassigned or used up, the run fails with an `::error::` naming the `EVALS` role; the owner
  reassigns it through the account rotation tool. The label run and the hill climb run on the key
  alone (Q14, Q53, as amended by the owner decision "Eval runs on a subscription token, case
  pruning, and how #18356 lands", 2026-11-23, in
  [owner-decisions.md](https://github.com/melodic-software/architecture/blob/main/docs/owner-decisions.md),
  extended to suite runs by
  [owner-decisions.md#L370](https://github.com/melodic-software/architecture/blob/9fecf3f103380aa38f9a7936c4209330f9ab4bcd/docs/owner-decisions.md#L370),
  and moved to the `EVALS` role, key first, by the owner decision "Dedicated eval lane
  credentials", [melodic-software/architecture#235](https://github.com/melodic-software/architecture/pull/235)).

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
- A dispatched suite run's `eval-browser-<run id>-<attempt>` artifact, kept 3 days, holds each
  run's final reply in `<plugin>/last-messages.jsonl` beside `results.json`, left out when the
  leak scan blocks it (`last-messages.mjs`).

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
- It stays `false`: every eval workflow is started deliberately (dispatch or the `eval: run`
  label), none runs on a schedule. `true` is the owner's emergency kill switch; sessions never
  change it (owner decision 2026-11-24, replacing the reset to `true` after a run). Scoping is
  unchanged: run only the cases the change affects (Q52, Q55).
