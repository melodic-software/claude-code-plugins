# Changelog: evals

## [0.3.10] - 2026-10-01

### Changed

- Dropped citations of the removed topic-docs convention and the `docs/specs` tree.

## [0.3.9] - 2026-10-01

### Changed

- **`plugin-eval` stops and hands off when a worktree-isolated session refuses `claude plugin eval`.**
  The new Worktree isolation section tells the agent not to retry or bypass the guard, to print the
  exact command for the user to run outside Claude Code, and to read the result back with the `read`
  action. The PowerShell fallback now applies only to a guard other than the worktree refusal.

## [0.3.8] - 2026-09-30

### Changed

- **`methodology`'s description opens with a presence-gated routing clause for the bundled
  `claude-api` skill's `hillclimb`.** It routes sweeping model and effort against an eval suite
  that already exists to `hillclimb` and keeps the case where the suite does not exist yet or its
  criteria are not yet measurable, the split its Boundary section states. `plugin-eval` gets no
  phrase: `plugin eval` is a CLI subcommand, which never enters the model's skill listing the gate
  reads.
- **The `claude-api` Boundary bullet in `methodology` no longer asserts that the subcommands ship
  with Claude Code.** It keeps the provenance class, what the subcommands do and how they are
  invoked, in the native-references template form.

## [0.3.7] - 2026-09-30

### Changed

- **`plugin-eval`: `case-authoring.md` splits graders by expectation.** A mechanical expectation gets a
  deterministic grader; a holistic one gets an `llm` judge.

## [0.3.6] - 2026-09-29

### Changed

- **`design`: says when a skill eval needs a no-skill baseline arm.** An `evals/evals.json` case grades
  the skill's output only. A comparative or whole-plugin claim routes to `/evals:plugin-eval`, whose
  with/without delta answers it.

## [0.3.5] - 2026-09-29

### Fixed

- **Changelog accuracy** for `0.3.4`, corrected in place. The entry said the `validate` argument-hint
  examples and defaults "now live in the skill body". The `argument-hint` was only shortened from
  `[eval-dir (default: evals/ under the plugin root)]` to `[eval-dir]`; the default it carried now sits in
  a new `**Arguments.**` line, and the Run it section already stated it.

## [0.3.4] - 2026-09-28

### Changed

- **Argument hints** on `validate` stay inside the 100-character house style
  ([#3542](https://github.com/melodic-software/claude-code-plugins/issues/3542)).
  The `argument-hint` was shortened from `[eval-dir (default: evals/ under the plugin root)]` to
  `[eval-dir]`; the default it carried now sits in a new `**Arguments.**` line, and the Run it section
  already stated it.

## [0.3.3] - 2026-09-28

### Changed

- **The native-surface presence gate reads "resolves in this session"** ([#4112](https://github.com/melodic-software/claude-code-plugins/issues/4112)). The `methodology` skill's `eval-design` reference named a native surface behind "resolves in your session", which addresses the reader. The gate now names the session instead, matching the canonical token that claude-ops' native-overlap self-check matches. Routing is unchanged.

## [0.3.2] - 2026-09-28

### Added

- **Fleet pipeline gap analysis** ([#3614](https://github.com/melodic-software/claude-code-plugins/issues/3614)).
  `docs/specs/evaluation-methodology-gap-analysis.md` records adopt / already-covered / rejected
  verdicts for each Agent Skills evaluation pipeline element against this fleet's `evals.json`
  corpus and `/evals:*` skills. Each adopt verdict is a proposal re-gated to the operator.

## [0.3.1] - 2026-09-25

### Changed

- Comment-only pass with /code-tidying:dissolve-comments: restating comments, history narration and ticket back-references removed from scripts and tests, over-budget rationale shortened. Every edit is certified comment-only by a token-level proof, so behavior is unchanged; the removed text is recorded in the commit bodies.

## [0.3.0]

### Added

- **`plugin-eval`**: guided practice around the Claude Code `plugin eval` command, which runs a
  plugin's cases with the plugin loaded and again against a no-plugin baseline and scores both. The
  skill preflights (CLI version against the floor the command requires, sandbox backend, target
  type), validates the case files before spending, estimates cost from cases times runs times arms
  against the configured ceiling, reads the delta first, and carries the iteration loop and a CI
  recipe. Two facts read from kept traces of the pilot suite are recorded in the body: the with-arm
  cannot `Read` the plugin's own `reference/` files, so a delta measures the hub `SKILL.md` alone,
  and the without-arm's cost on a knowledge case comes from the bundled `claude-api` skill firing.
- **`validate`**: a static check over a plugin's eval case files that makes no model call and spends
  nothing, reporting the load failures the binary rejects and the authoring mistakes its docs name.
- A pilot eval suite at `plugins/evals/evals/`: three read-only cases, each pairing an outcome
  grader with a path grader, measuring what this plugin contributes over a no-plugin baseline.
- `userConfig`: `max_cost_usd` (number, default 5), the ceiling passed to the CLI per invocation,
  and `unlimited_cost` (boolean, default false), which drops the ceiling and keeps the estimate.

### Changed

- The plugin description and the README now state what runs where: the CLI runs and scores,
  `/evals:plugin-eval` preflights, prices, validates, and reads the delta, `/evals:validate` is the
  zero-spend check. This replaces the runner-boundary disclaimer both older skills carried, which
  the command's release made false.
- **`design`**: the description and the "What this skill does NOT do" list drop that disclaimer, a
  plugin target hands to `claude plugin eval init`, and `## Next` routes by what was scaffolded. The
  per-skill `evals/evals.json` it emits is still a separate format the CLI does not read.
- **`methodology`**: the scope boundary points at `/evals:plugin-eval` for running and scoring, and
  a `## Next` section names `/evals:design` and `/evals:plugin-eval`. The skill remains knowledge,
  not a runner.

## [0.2.4]

### Changed

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.
- **The plugin's prose drops its em dashes.** Eight surfaces were rewritten: this changelog, the README, both SKILL bodies, and the four `skills/methodology/reference/` documents. Wording only, with no change to any criteria dimension, recipe, or grading rule. Both skill bodies keep every trigger phrase byte-identical (19 across the two, confirmed by `check-skill.sh`), and the quoted cookbook and Likert strings are unchanged inside their quotes. Four headings changed anchor; nothing in the repository linked to them. The released sections corrected in place are 0.2.0 and 0.1.0: their wording changed, their facts did not.
- **`skills/methodology/SKILL.md` says which detail must be current instead of calling it load-bearing.** It now reads "any detail that must be current", matching the wording the same body already uses a few lines above.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md`, every `skills/*/SKILL.md`, and the `skills/methodology/reference/` tree.

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
  declaring it only restated the path while registering a second, unnamespaced command. The
  slash-command picker then echoed that back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## 0.1.0

- Initial release.
- `/evals:methodology`, the knowledge router distilled from Anthropic's "Define success criteria and
  build evaluations" (platform.claude.com, fetched 2026-08-08) and the evals cookbook
  (`anthropics/claude-cookbooks` `misc/building_evals.ipynb`): four reference spokes
  (success criteria, eval design, grading methods, recipes), a no-load quick decision guide, and a
  maintainer `update` drift-check action.
- `/evals:design` interviews for specific/measurable/achievable/relevant success criteria, then
  scaffolds a criteria doc plus a graded eval suite: `cases.jsonl` + README for an LLM app, or
  `evals/evals.json` in the marketplace schema shape for a consumer-authored Claude Code skill.
  Ships evals covering criteria-first routing, schema-shape emission, grading-ladder choice,
  golden-answer refusal, runner-boundary honesty, no-clobber, and LLM-grader hygiene.
- Eval-warrant verdicts: `design` warranted (judgment-bearing interview/routing/refusal contract);
  `methodology` explicit skip (pure-reference knowledge router, per the migration playbook's
  warrant policy).
