# Changelog — evals

## [0.2.3]

### Added

- **`methodology`**: an "Effort as an eval axis" section in `reference/eval-design.md`
  (sweep effort and model together on a non-saturated suite; a flat cost-performance curve
  means the task is not thinking-bound; the bundled `claude-api` `hillclimb` subcommand
  automates the search, bundled-only as of 2026-09-09), plus the routing-table keywords for
  it. Adopted from the vetted ClaudeDevs cost-performance article
  (`docs/upstream/claudedevs-cost-performance.md` in the marketplace repository).
- **`methodology`**: a `## Boundary, the bundled claude-api skill` section stating the
  composite posture with the bundled `hillclimb` and `build-eval` subcommands (this skill owns
  eval design and grading method; the bundled subcommands own the automated search once a
  suite exists; run both when a request spans them), with a mutation gate and an availability
  rule that never assumes the bundled skill resolves. The hillclimb citation in
  `reference/eval-design.md` is now gated on the bundled skill resolving in the session.

## [0.2.2]

### Added

- **`design`**: a `## Next` section naming the skill that normally runs after this one, in
  the mention-only shape the skill-body rule describes.

## [0.2.1]

### Changed

- methodology: the grading reference and the eval-design reference keep the upstream recipes and add the current-model caveat beside each: a grader that thinks by default needs no `<thinking>` tag instruction, and a `max_tokens` sized to fence a bare integer can cut a thinking model off before its answer.
- design: the Phase 3 grading gate asks for a reasoning-then-discard instruction only where the grader model does not already think before answering; eval case 7 asserts the conditional form.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.2.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## 0.1.0

- Initial release.
- `/evals:methodology` — knowledge router distilled from Anthropic's "Define success criteria and
  build evaluations" (platform.claude.com, fetched 2026-08-08) and the evals cookbook
  (`anthropics/claude-cookbooks` `misc/building_evals.ipynb`): four reference spokes
  (success criteria, eval design, grading methods, recipes), a no-load quick decision guide, and a
  maintainer `update` drift-check action.
- `/evals:design` — interviews for specific/measurable/achievable/relevant success criteria, then
  scaffolds a criteria doc plus a graded eval suite: `cases.jsonl` + README for an LLM app, or
  `evals/evals.json` in the marketplace schema shape for a consumer-authored Claude Code skill.
  Ships evals covering criteria-first routing, schema-shape emission, grading-ladder choice,
  golden-answer refusal, runner-boundary honesty, no-clobber, and LLM-grader hygiene.
- Eval-warrant verdicts: `design` warranted (judgment-bearing interview/routing/refusal contract);
  `methodology` explicit skip (pure-reference knowledge router, per the migration playbook's
  warrant policy).
