# Changelog: evals

## [0.5.4] - 2026-10-04

### Changed

- **Upstream plugin doc links repointed to the split `plugins/` pages ([#5962](https://github.com/melodic-software/claude-code-plugins/issues/5962)).** The README options block now links `plugins/cli-reference#plugin-install` for the `--config` flag, since the old `plugins-reference` page no longer carries that section, and `plugins/manifest-reference#user-configuration` for the `userConfig` schema.

## [0.5.3] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.5.2] - 2026-10-03

### Changed

- `skills/plugin-eval/scripts/calibrate-judge.test.sh`, `skills/plugin-eval/scripts/run-validity.test.sh`, and `skills/validate/scripts/validate-cases.test.sh` declare the files they read without naming them in `# test-scope:` headers, so CI's test selection runs them when one of those files changes. Nothing the plugin runs changed.

## [0.5.1] - 2026-10-03

### Changed

- Shared `prerequisites.sh`, `prerequisites.ps1` synced ([#5843](https://github.com/melodic-software/claude-code-plugins/issues/5843)); no change to this plugin's own behavior.

## [0.5.0] - 2026-10-02

### Added

- `prerequisites.json`, declaring the external tools this plugin runs and what stops working
  without each, and the generated `lib/prerequisites.mjs` checker with its `.sh` and `.ps1`
  stubs that read it ([#5841](https://github.com/melodic-software/claude-code-plugins/issues/5841)).

## [0.4.1] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.
- The plugin description is 500 characters or fewer, the limit claude.ai's marketplace sync enforces.
- The `validate` skill description writes `samples/GRADER.json` instead of an angle-bracket placeholder, which claude.ai reads as an XML tag.

## [0.4.0] - 2026-10-02

### Added

- **`plugin-eval` reports noise before a gain counts.** A new `scripts/noise-report.py` reads
  `aggregate-result.json` and prints an interval on each arm's mean, a paired interval on the
  with-versus-without difference, "within noise" when that interval contains 0, "n too small to
  call" below 3 cases or when every per-case delta is equal, a warning when the without-arm mean
  is 0.95 or higher, a pass-count view at the run's threshold, and judge-vote agreement per `llm`
  grader. `## Reading the delta` tells the reader to run it.
- **The preflight warns when the tested model and the judge are the same model.** It is advice
  only and never blocks a run.
- **`design` routes by repository kind and has every input approved.** A Claude API app is told
  to type `/claude-api build-eval`; a skill or plugin repository continues here and runs through
  `plugin-eval`. Candidate cases render for approval through a new `scripts/render-review.py`,
  Markdown by default and escaped HTML as the option. A Markdown table cell escapes link and image
  syntax, so case text cannot load a remote image or hide a link behind other text; a bare URL
  still shows as itself. Raw transcripts stay out of cases in a public repository or one of
  unknown visibility. Graders are checked against a handful of cases before their scores are
  trusted.
- **`methodology` points at the bundled hillclimb guides.** A new `reference/hillclimb.md` links
  each step at a pinned commit and states only this plugin's facts; a new
  `reference/local-decisions.md` holds this plugin's defaults and source conflicts. The skill
  routes by repository kind.
- **Six settings:** `split_policy`, `interval_method`, `review_format`, `grader_run_twice`,
  `same_model_warning` and `labeled_grader_check`.
- **The suite grows to 30 cases.** 21 are hard cases, each saying why it is hard; 4 are routine
  guards where the base model already answers well; 4 are near-miss controls that must not invoke
  an evals skill; and 1 is a knowledge case. `noise-before-gain` is the one a person judged hard: a
  model tends to take a small gain over a near-ceiling baseline at face value.
- **Every `llm` grader has labeled samples.** All 47 hold must-pass and must-fail answers in
  `samples/<grader>.json`, so each rubric can be calibrated against them.
- **`plugin-eval` calibrates a judge.** A new `scripts/calibrate-judge.py` builds one case per
  labeled sample, whose agent replies with the sample word for word, and scores the judge's
  verdicts against the labels: agreement, false positives and negatives, split votes, runs whose
  reply was not the sample (whitespace and bold markers aside), and samples never judged. A grader under 90% agreement prints a
  `FAIL grader` line and the script exits 1. A `case.yaml` grader name that is not one path
  segment is skipped with a note, so a suite cannot write outside `--out`. `## Calibrating a
  judge` gives the commands.
- **`plugin-eval` checks a run is valid before its score counts.** A new
  `scripts/run-validity.py` reads `aggregate-result.json` and the kept traces and prints VALID or
  INVALID: an incomplete or empty run, skipped paid graders, an errored run, a row count that
  differs from `--runs`, any permission denial in a trace, or a should-trigger case whose skill did
  not fire makes it INVALID; split judge votes, an unrecorded judge model and ceiling cases are
  warnings. The run command now keeps traces (`--keep-temp`).
- **`validate` tests free graders offline against sample answers.** Each case can hold
  `samples/<grader>.json` with answers that must pass and answers that must fail; a `regex`,
  `tool_used`, `tool_order` or `file_exists` grader that rejects a must-pass answer or accepts a
  must-fail one is a FAIL, and one with no sample file is a WARN. `llm` graders with samples get a
  calibration WARN, since only a paid judge run can check them.
- **`validate` warns on the two undocumented `prompt.md` keys.** `artifact_publish` and
  `growthbook_overrides` load but are not on the reference page, so they can change without notice.

### Changed

- **The pilot suite's graders are fixed.** `methodology-wording` stays a `regex` but is an unscored
  with-arm indicator (`arm: with-only`), and a new `llm` grader, `grading-choice`, scores answer
  quality; `noise-verdict` is replaced by the `not-established` and `ceiling` graders, so one judge
  error costs half a run; `four-properties` requires the target number itself to be justified. Each
  case's description says what it measures, and the three `llm`-graded tracked cases name `--judge-model sonnet`.
- **`run-validity` exempts a no-trigger control.** A case is a control when its `prompt.md` tags or
  description say so, or when it has a max-0 `Skill` grader aimed at this plugin's own skills and
  no grader requiring a call. A guard on another skill does not make a control.
- **The four controls score their must-not-invoke guard in both arms** (`arm: both`), since
  staying quiet is what a control measures. The routing cases' guards stay unscored indicators.
- **`methodology` states the target-number rule.** A target number is realistic only when a
  measured baseline, a prior result, a benchmark or expert review justifies it; a grader checked
  against labels, or a miss called severe, does not.
- **The `plugin-eval` hub records the reference-read denial.** A path-scoped `Read` grant does not
  lift the refusal of a spoke file, so anything a case depends on goes in the hub.
- **The cost anchor for a fresh suite is 0.1 USD per run in either arm**, judge calls included,
  called headroom. The old 0.8 USD per without-run applies only when a kept trace shows the
  without-arm loading a large skill.
- **CI pins a full model ID for the agent and the judge**, never an alias such as `sonnet`.
- **`reading-results.md` says to count rows per arm**, never `runsPerCase`.
- **`plugin-eval`'s description names comparing two runs and asking whether a gain is real**, so
  those questions route to it.
- **Each "volume" line says volume means cheaper grading, never easier cases.**
- **The design skill's tone test case expects a checkable pass/fail rubric**, not a 5-point
  scale.
- **The "not yet public" distribution records are pointers to the published guides.**
- **The hubs answer without opening a spoke or a script**, since an eval run can read only the
  hub. `validate` lists the `prompt.md` keys (`timeout_seconds`, not `timeout`), the grader types
  and their options, and the bounds; a pattern check is `type: regex` with `pattern`.
  `methodology` answers from its quick guide when it covers the question, and a rewritten
  criterion grounds its target the way the success-criteria page's Achievable property allows;
  with no data given it states the target relative to the current baseline, never a made-up
  baseline figure, expert agreement or X/Y/Z placeholders. `plugin-eval` answers a CI question from its CI section,
  names the pass-count line as the only one the interval setting changes, says an estimate under
  the ceiling starts with `--max-cost-usd` and no prompt, says to rerun cases a usage limit
  zeroed once it resets, and says the unavailable message leaves no access to request.
- **Descriptions route more asks to the skill that answers them.** `plugin-eval` names a
  `claude plugin eval` refused by Bash or in a worktree, and whether it can measure CLAUDE.md or
  rules; `methodology` and `design` name evals for a service that calls the Messages API and the
  route for each part of a repository.
- **`run-validity` prints the path a denied call aimed at**, and a denial is a warning when that
  run scored the same as every denial-free run of its case in the same arm. A with-arm denial
  aimed at, under or above the plugin's directory or at no path, or any denial with a different
  score or nothing to compare, stays a FAIL. On an INVALID line those warned cases are marked
  "warnings only, not counted".
- **The hubs lead with the right first step.** `methodology` and `design` present the reference
  files as background for a human reader, and both give `/claude-api build-eval` as a Claude API
  app's first step, ahead of any hand-written criteria or cases. `plugin-eval` answers for the
  platform the user states, never the session's own host, and with a null `error` runs the
  validity gate and the noise report before saying anything about the cases.

## [0.3.13] - 2026-10-02

### Changed

- The `unlimited_cost` option title is a noun phrase, "No cost ceiling", per the plugin option
  naming convention (`docs/conventions/plugin-option-naming/`).

## [0.3.12] - 2026-10-02

### Fixed

- The `design` `argument-hint` uses Claude Code's official bracket notation: the target changes
  from optional to required, `<app|skill <name>|plugin <path>>`, because a run with no target asks
  for one, and the `target:` label is dropped.
- The `plugin-eval` `argument-hint` uses Claude Code's official bracket notation: it keeps
  alternatives inside brackets with an unspaced `|`.

## [0.3.11] - 2026-10-01

### Changed

- References to the `claude-config`, `claude-memory` and `claude-ops` plugins now use their new
  names, `harness-config`, `harness-memory` and `harness-ops`.

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
