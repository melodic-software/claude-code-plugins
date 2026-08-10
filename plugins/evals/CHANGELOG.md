# Changelog — evals

## [0.2.1]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

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
