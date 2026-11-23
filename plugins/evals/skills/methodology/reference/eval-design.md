# Eval design

This repository's reading of eval design. Anthropic's guidance is read live.

- **Pointer**: for eval anatomy, golden answers, edge cases and the design principles, fetch
  [Build evaluations](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#build-evaluations)
  and [Eval design principles](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#eval-design-principles).
  The evals cookbook is `anthropics/claude-cookbooks` `misc/building_evals.ipynb`.

This repository's own defaults and source-conflict records: [local-decisions.md](local-decisions.md).

## Decisions

- A case set mirrors the real task distribution and names its edge cases; a golden answer is an
  exact answer for code-graded cases and rubric-instructions for LLM-graded or human-graded ones.
- Volume means cheaper grading per case, never easier cases: a hard case stays in for a stated
  reason (correlate with
  <https://claude.dev/blog/automating-eval-design-and-hillclimbing#adversarial-sampling>).
- Design for cheap re-runs. Writing cases is a one-time cost and grading recurs on every run, so
  constrain the output format until grading is code, and leave `max_tokens` headroom for a model
  that thinks rather than fencing the answer with a tight limit.
- Generated cases get a human sign-off: generation scales authoring, it does not replace judgment
  about what the distribution should be.

- **Pointer**: when sizing `max_tokens` for a model that thinks, fetch
  [Budget rules and tuning](https://platform.claude.com/docs/en/build-with-claude/extended-thinking#budget-rules-and-tuning).

## Effort as an eval axis

For applications on models with an effort parameter, effort is an eval dimension, not a fixed
setting. On a non-saturated suite, sweep model and effort together, read cost against score, and
pick the cheapest model-and-effort pair that holds the target; sweep the two together because the
cheapest such pair can sit at any model. A saturated suite cannot show where a cheaper pair starts
losing score.

- **Pointer**: when reading an effort sweep's cost-against-score curve, or choosing between a
  stronger model at lower effort and a weaker one at higher effort, fetch
  [Tune effort](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#tune-effort).

When the bundled `claude-api` skill resolves in this session, its `hillclimb` subcommand
automates this search over a suite; this repository's step map for it is
[hillclimb.md](hillclimb.md). The routing between that surface and this skill is the `## Boundary`
section in `SKILL.md`.

Distribution record. The subcommands and their guides are published:

- **Pointer**: for the `/claude-api` subcommands, see
  <https://code.claude.com/docs/en/skills#work-on-claude-api-projects>; for the guides, see
  [`eval-hillclimb.md`](https://github.com/anthropics/skills/blob/main/skills/claude-api/shared/evals/eval-hillclimb.md)
  and
  [`build-eval.md`](https://github.com/anthropics/skills/blob/main/skills/claude-api/shared/evals/build-eval.md).
- **As of**: 2026-10-01
- **Recheck trigger**: the Claude API skill docs page
  (<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/claude-api-skill>) lists
  `build-eval` and `hillclimb`; then repoint there.
