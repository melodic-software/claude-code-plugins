# Changelog — evals

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
