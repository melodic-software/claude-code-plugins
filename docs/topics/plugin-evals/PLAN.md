# plugin-evals

Topic slug `plugin-evals`. Branch `plugin-evals`, one worktree, one PR. Interview locked 2026-09-11.
Inputs and ledgers: `.work/plugin-evals/INDEX.md`.

## Brief

### TLDR

Adopt `claude plugin eval` (Claude Code 2.1.269) in this marketplace as a guided, repeatable,
metric-driven practice: a workflow skill and a static case validator in `plugins/evals/`, a pilot
suite on the `evals` plugin, and the removal of every recorded decision or statement the command's
release invalidates.

### Goal

A user of this marketplace can take any plugin (or a standalone skill or agent, wrapped as one),
set up an eval suite, validate it without spending, run it under a cost policy they chose, read the
with-versus-without-plugin delta correctly, and iterate on the plugin from that number. This repo
does the same for itself, starting with one pilot suite.

### Constraints

- The plugin is the only unit the harness loads and ablates. Skills and agents are evaluated through
  the wrap route (`claude plugin init <name>` or a minimal `.claude-plugin/plugin.json`); hooks and
  commands as plugin components, hooks with the docs' advisory caveat; `CLAUDE.md` and rules are out
  of scope and routed to `claude-config:unhobble`.
- Both new pieces live in `plugins/evals/`. `skill-quality:check validate-evals` keeps the
  skill-creator `evals.json` format; the two descriptions cross-reference. `evals:design` hands plugin
  targets to `claude plugin eval init` rather than scaffolding the new format.
- Native Windows has no sandbox backend; cases that grant Bash, Write, or Edit are refused there.
  Preflight detects the backend and says so; read-only suites run locally; Bash-granting suites run
  on another machine or a Claude cloud session.
- Cost: a plugin user-config ceiling passed as `--max-cost-usd` (default 5 USD) and an unlimited
  option that removes the ceiling only; the estimate is always shown; with unlimited set the run
  starts without waiting. The ceiling bounds a list-price estimate, not subscription usage.
- Every volatile fact about the command (flags, schema bounds, exit codes, sandbox behavior,
  version floor) is carried as a four-part upstream-drift record per
  `.claude/rules/skill-bodies-state-current-rules.md`; no date-conditional prose, no bare pinned
  version as fact. The feature shipped 2026-09-11 and has no independent corroborating source yet.
- A `plugin eval` record is added to `docs/native-surfaces/records.json` before any skill references
  the command.
- `evals/results/` is gitignored per the docs; any committed pilot evidence is a stated exception.
- Recorded decisions reopened, each in the open: the migration playbook "Evals" deferral becomes an
  adoption record with `melodic-software/medley#1418` linked, not closed; every "does not execute
  evals" statement in the `evals` plugin is replaced; the unhobble routing in
  `docs/specs/prompt-audit-skills-2026-09.md` narrows to `CLAUDE.md` and rules; a sweep removes
  anything else the change invalidates.
- No tracker writes without explicit say-so. The PR opens as a draft and is flipped when done.
- New skill leaf names are registered in `scripts/skill-leaf-name-registry.txt` if shared across
  plugins; the `evals` plugin CHANGELOG and version are bumped.

### Acceptance criteria

- The guide skill's preflight, run on this machine, reports the Claude Code version, the absence of
  a sandbox backend, and the target type correctly for a plugin, a wrapped skill, and a rules target
  (refused with the unhobble pointer).
- The static validator flags an unknown `prompt.md` frontmatter key, a duplicate grader name, and a
  case with no grader, and passes the pilot suite, with no model call.
- The pilot suite on `plugins/evals/` runs locally under the ceiling, writes `aggregate-result.json`
  with a delta per case, and at least one case shows a positive delta.
- IF the sandbox backend is absent and a case grants Bash, THEN the guide refuses the run before any
  spend and names the reason and the cloud route.
- WHILE the cost option is unlimited, the pre-run estimate is still shown and the run proceeds
  without a prompt.
- No tracked file still states that this marketplace does not execute evals, and no tracked file
  still describes `claude plugin eval` as early access or deferred.
- `scripts/affected-tests.sh --run`, `scripts/check-changed-skills.sh`, the skill-quality check, and
  the leaf-name check pass on the branch.

### Captured assumptions

- "Let's start there" in round 2 was read as accepting Q8 through Q11 as recommended; stated to the
  user, not corrected.
- The pilot suite's read-only cases are enough to produce a meaningful delta for the `evals` plugin;
  if they are not, the pilot moves to the cloud follow-up rather than granting Bash here.
- The acceptance-criteria format resolved to `free-text` (default) because the repo declares no
  convention-home pointer.

### Out-of-scope

- Evaluating `CLAUDE.md` or rules through the harness, including an `append_system_prompt` shim.
- A rollout of eval suites across the other plugins in this repo; one pilot only.
- Retargeting `evals:design` to emit the plugin-eval case format.
- Any change to the `planning` plugin's emoji markers.

### Deferred questions

- Q12 (arbiter: USER-RESERVED): empirical execution of Bash-granting and Write-granting cases,
  which native Windows refuses. Worked in a Claude cloud session or on a Linux/macOS machine after
  this PR; findings feed corrections to the guide. Captured here and in the PR body; a GitHub issue
  is opened only when the user says so at PR time.

## Plan

### Goal

**What**: two skills and one script in `plugins/evals/` (`evals:plugin-eval`, the guided runner, named
after the command and clear of the bundled `run` skill; `evals:validate`, the static case validator), a read-only pilot suite under `plugins/evals/evals/`, a `plugin eval` row in
the native-surfaces store, and the replacement of every statement the command's release invalidated.
**Why**: the Brief's goal is a repeatable, metric-driven practice; the CLI ships the runner but not the
guidance, the no-spend validation, the cost policy, or the Δ-reading discipline, and this repo still says
in five places that nothing executes evals.

### Standards grounding

No standards index exists (`.claude/standards.yaml` and `docs/standards/` absent), so this is rung 4 of
the resolution ladder: inferred from `docs/conventions/`. Offer at approval: persist the inference as
`.claude/standards.yaml` pointing at `docs/conventions/`; nothing is written unprompted.

| Surface | Sections cited | Layer |
|---|---|---|
| `docs/conventions/native-references/README.md` | the description phrase, the Boundary section, self-containment, enforceability | team |
| `docs/conventions/upstream-drift/README.md` | required parts, the observability bar, a date is never authority | team |
| `.claude/rules/skill-bodies-state-current-rules.md` | whole rule, `## Next` grammar | team (fires on `plugins/*/skills/**`) |
| `docs/conventions/invocation-mode/README.md` | the default, cross-skill invocation phrasing | team |
| `docs/conventions/seam-phrasing/README.md` | the shape (gate, fallback, ownership) | team |
| `docs/conventions/topic-docs/README.md` | two tiers, close-out, redaction bar | team |
| `docs/conventions/pre-pr-ordering/README.md` | the order | team |
| `docs/conventions/shell-test-helpers/README.md` | per-plugin helpers, own exit taxonomy | team |
| `.claude/rules/pr-body-contract.md`, `.claude/rules/vendor-docs-are-not-style.md` | whole rule | team (ambient) |

### Approach

Integration-first: the riskiest claim is that read-only cases produce a positive Δ, so the pilot runs
right after its prerequisites and before any skill body is written. The store row lands before any skill
references the command and stays registry-only (both `baked` flags false): the convention's gate token is
a condition on the model's skill listing, which a shell subcommand never enters, so the skill gates on
the CLI itself (version floor in preflight) and never carries the listing phrase. A confirming pilot pass
runs after the plugin's skills and descriptions change, since the Δ measured in Phase 2 is against the
plugin as it was.

#### Files affected

| File | Action | What changes |
|---|---|---|
| `docs/native-surfaces/records.json` | Modify | add the `plugin eval` row (class `builtin-command`, marker `gated`, verdict `complementary`, component `evals`/`plugin-eval`) |
| `docs/NATIVE-SURFACES.md` | Regenerate | `overlap.py generate` after the row lands |
| `.gitignore` | Modify | `plugins/*/evals/results/` |
| `plugins/evals/evals/<3 cases>/prompt.md`, `graders/*.md` | Create | pilot suite |
| `docs/topics/plugin-evals/verification/pilot.md`, `verification/preflight.md` | Create | distilled pilot evidence (Δ per case, cost, version); the preflight transcripts for criteria 1, 4, 5 |
| `plugins/evals/skills/validate/{SKILL.md,scripts/validate-cases.py,scripts/test_validate_cases.py,scripts/validate-cases.test.sh,evals/evals.json}` | Create | static validator |
| `plugins/evals/skills/plugin-eval/{SKILL.md,reference/*.md,evals/evals.json}` | Create | guided runner |
| `plugins/evals/.claude-plugin/plugin.json` | Modify | description, `userConfig` (two keys), version 0.3.0 |
| `plugins/evals/CHANGELOG.md`, `README.md` | Modify | 0.3.0 entry; "does not execute" section becomes the runner section |
| `plugins/evals/skills/design/SKILL.md`, `skills/methodology/SKILL.md`, `skills/design/evals/evals.json` | Modify | drop the "does not execute" clauses; `## Next` names `evals:plugin-eval`; the wrap route for plugin targets |
| `docs/MIGRATION-PLAYBOOK.md` L350-458 | Modify | deferral becomes an adoption record; `medley#1418` linked |
| `docs/specs/prompt-audit-skills-2026-09.md` (~L614), `docs/specs/provenance-capability-matrix.md` (~L201), `docs/specs/write-for-agents-brief.md` (~L57), `docs/specs/provenance-design-threads.md` (~L107) | Modify | one dated note each pointing at the adoption record |
| `docs/CATALOG.md` | Regenerate | `node scripts/generate-catalog.mjs` after the manifest change |
| `plugins/playbooks/skills/skill-authoring/reference/authoring-guidance.md` L221-234, `plugins/playbooks/CHANGELOG.md`, `plugins/playbooks/.claude-plugin/plugin.json` | Modify | the fired recheck trigger ("the docs page documents the command") is honored: fact restated, as-of refreshed, patch bump |
| `docs/upstream/aihero-course.md` L314, `package.json` | Keep | upstream digest; the pin only serves cloud-bootstrap marketplace registration, never evals |

#### Dependencies

- Claude Code 2.1.269 on the machine that runs the pilot; this machine has it and no sandbox backend.
- `node_modules/.bin/markdownlint-cli2`, `jq`, `python3` 3.8+ (`overlap.py`, the validator), `node`
  (catalog), `scripts/run-ruff.sh`.
- Downstream: `scripts/check-changed-skills.sh` (needs `evals/evals.json` and an explicit invocation-mode
  key per new skill), `scripts/check-changelog-parity.sh --check-bump`, `overlap.py self-check`,
  `scripts/check-skill-leaf-names.sh --check` (no registry change: `plugin-eval` and `validate` collide with no
  plugin), `scripts/run-plugin-tests.sh` (discovers the new `.test.sh`).

### Phase 1: Prerequisites the later phases cite [TODO]

- Add the `plugin eval` row to `docs/native-surfaces/records.json`, shaped like the `skill-doctor` row:
  `native {name: "plugin eval", class: builtin-command, markers: [gated]}`, `component {plugin: evals,
  skill: plugin-eval, kind: skill}`, `verdict: complementary`, evidence from the 2.1.269 `--help` text and
  the docs page, `observation {class: extraction, detail: "<binary path> --help at 2.1.269 ..."}` (the
  detail carries the version string the parity script keys on), a recheck trigger naming the next
  release, `baked` both false, `budget_caveat: true`. The reason states the split: the CLI runs and
  scores; `evals:plugin-eval` preflights, validates, prices, and reads Δ; and why no listing phrase is
  baked (a shell subcommand is not a listing surface). Check `overlap.py detect` does not pair the new
  skill with the bundled `run` row; the leaf `plugin-eval` avoids it.
- Regenerate `docs/NATIVE-SURFACES.md`.
- Add `plugins/*/evals/results/` to `.gitignore` (Edit tool; the worktree guard refuses Bash mentioning
  `.gitignore`).
- Commit `docs/topics/plugin-evals/design/design-resolution.md` and this plan with the phase.
- **Sanity Check:** `python3 plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py self-check`
  exit 0; same script `generate --check` exit 0; `jq '.rows[] | select(.native.name=="plugin eval") | .baked'
  docs/native-surfaces/records.json` prints both flags false; `git check-ignore -q
  plugins/evals/evals/results/x.json` exit 0.

### Phase 2: Pilot suite and the measured Δ (integration slice) [TODO]

- Term-uniqueness probe first, near-zero spend: the methodology references distill public Anthropic
  pages, so the without-arm may already know them. Pick candidate terms from repo-original passages
  (the current-model caveats in `reference/grading.md`, the routing table, `reference/recipes.md`), ask
  a plain `claude -p` session (no plugin) the case-1 question, and keep only a term that does not appear
  unprompted. If no such term exists, the outcome grader cannot separate the arms by knowledge; see the
  fallback below before spending on a full pass.
- Three read-only cases under `plugins/evals/evals/`, `allowed_tools: [Read, Glob, Grep, Skill]`,
  `max_turns: 10`, `runs: 3`, each pairing one outcome grader with one path grader:
  1. `grading-method-choice`: a question `evals:methodology` answers from `reference/grading.md`; outcome
     grader `regex` (`arm: both`) on the probed term; path grader `tool_used` on `Skill` with
     `input_match` for methodology.
  2. `measurable-criterion`: rewrite a vague success criterion; outcome grader `llm` (`arm: both`) with
     criteria taken from `reference/success-criteria.md`; path grader as above.
  3. `control-no-trigger`: a pytest-fixture question that must not invoke the plugin; `tool_used` on
     `Skill` with `min: 0`, `max: 0`, `arm: both`, plus a `regex` outcome grader.
- Estimate before the run, per the H-12 formula: 3 cases × 3 runs × 2 arms = 18 agent runs plus 18 judge
  calls for the one `llm` grader; the recorded datum is 0.41 USD for one case at 6 runs, so one full pass
  is roughly 1.5 USD. `--max-cost-usd` is checked per invocation, so it bounds one pass, not the phase:
  each pass runs under `--max-cost-usd 2`, Phase 2 stops at three passes (6 USD), and the whole pilot
  including the Phase 6 confirming pass is capped at 8 USD, tallied in `pilot.md` from each JSON's
  `costUsd`.
- Run from the PowerShell tool (the harness worktree guard refuses Bash commands containing `eval`):
  `claude plugin eval plugins/evals --trust-plugin --json <scratchpad>/pilot-1.json --max-cost-usd 2
  --threshold 0.8 --no-publish`. The JSON is the oracle, never the exit code (exit 1 is overloaded and
  the default threshold of 1.0 fails a suite on one imperfect run). `--trust-plugin` on a path inside a
  git repository trusts the whole repository; whether that persists past the run is unrecorded, noted in
  `pilot.md` and the skill's Gotchas. Read Δ first; if `tool_used: Skill` fails in the with-arm, fix the methodology
  description, not the case; if Δ ≤ 0 with the indicator passing, tighten the rubric or switch the outcome
  grader to `regex`; rerun with `--case <name> --runs 1 --ablation none`, confirm at 3 runs. At most two
  full reruns inside the ceiling.
- Write `docs/topics/plugin-evals/verification/pilot.md`: per-case WITH, W/OUT, Δ, `costUsd`,
  `claudeVersion`, `partial`, and what changed between passes. Distilled values only; no machine paths.
- If the probe finds no separating term, or no positive Δ survives two reruns: stop, keep the suite,
  record the negative result, and propose rewording acceptance criterion 3 to the indicator form (the
  `tool_used: Skill` grader fires in the with-arm and not in the without-arm). A cloud session is not a
  fallback for this: the same base model knows the same material there. `[FALLBACK — confirm or override]`
- **Sanity Check:** the final JSON has `partial == false`, `cases | length == 3`, every
  `cases[].aggregates.delta` present, at least one `> 0`, every `cases[].arms.*[].error` and `.aborted`
  null, no run with `skippedPaidGraders == true` (a mid-suite rate limit zeroes runs without marking
  `partial` and can inflate Δ), the sum of `costUsd` over the phase's JSON files at most 6; `git status --porcelain
  plugins/evals/evals/results` prints nothing (ignored); `pilot.md` exists with a Δ row per case.

### Phase 3: Static validator, script first, thin skill on top [TODO]

Review: code-design

- `plugins/evals/skills/validate/scripts/validate-cases.py`: Python 3.8+, standard library only (the
  shape of `plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py`, which carries its own
  frontmatter reader; PyYAML is provisioned in CI only). Exit and output contract from the design
  resolution (0/1/2, `FAIL`/`WARN` lines, header-derived `--help`). A bounded YAML-subset parser:
  scalars, quoted scalars, flow lists, flow mappings, block lists including lists of mappings (the
  `case.yaml` `graders:` list, the only place a duplicate grader name can arise), block mappings three
  levels deep. Anything it cannot parse is `FAIL <file>: frontmatter not parsed (<construct>); simplify
  or run the CLI`, never a WARN at exit 0: a validator must not green-light what it did not read. FAIL
  tier mirrors the binary's rejections, WARN tier the documented mistakes. Lint through the pinned
  wrapper `scripts/run-ruff.sh check`.
- TDD: `scripts/test_validate_cases.py` (`unittest`) first, wrapped by `validate-cases.test.sh` so
  `scripts/run-plugin-tests.sh` discovers it. Fixtures are built by the test in a temp directory from
  inline strings (no tracked fixture tree: `*.yaml` has no no-suite entry, a tracked `prompt.md` fixture
  would be linted as prose, and `check-orphaned-fixtures.sh` scans `*/evals/fixtures/*`): `unknown-key`,
  `duplicate-grader` (via `case.yaml` graders), `no-grader`, `over-bounds`, `bad-env-key`,
  `precedence` (`case.yaml` plus `prompt.md`), `unparsed` (an anchor or multi-line scalar), `clean`;
  then the script until green; then the tracked pilot suite as the live fixture.
- `SKILL.md` (`disable-model-invocation: false`, description under 1024 codepoints with trigger phrases,
  seam sentence to `skill-quality:check validate-evals` for the other format behind an installed-ness gate,
  `## Next` → `evals:plugin-eval`, `## Gotchas`), plus `evals/evals.json` in the skill-creator format.
- **Sanity Check:** `bash plugins/evals/skills/validate/scripts/validate-cases.test.sh` exit 0; `python3
  plugins/evals/skills/validate/scripts/validate-cases.py plugins/evals/evals` exit 0; the test asserts
  exit 1 and a line matching `^FAIL .*(unknown frontmatter key|duplicate grader|no grader|runs|not
  parsed)` per FAIL fixture; `scripts/run-ruff.sh check plugins/evals/skills/validate/scripts` exit 0;
  `plugins/skill-quality/scripts/check-skill.sh plugins/evals/skills/validate` reports no FAIL. The
  portability scanners skip `*/evals/*`, which swallows this whole plugin by name; they are not evidence
  here (recorded under Open questions).

### Phase 4: The guided runner skill [TODO]

Review: code-design

- `plugins/evals/skills/plugin-eval/SKILL.md`, under 500 lines, actions `preflight` | `validate` | `run`
  (default) | `read <json>` | `ci` | `init`. Body order: preflight report (fields per the design
  resolution; platform-shaped sandbox detection, since no CLI string is recorded), target routing table
  (plugin, wrapped skill, wrapped agent, hooks advisory, `CLAUDE.md` and rules refused with the
  `claude-config:unhobble` pointer behind an installed-ness gate), cost (formula, ceiling from
  `${user_config.max_cost_usd}` rendered as prose and passed by hand, `${user_config.unlimited_cost}`
  drops the flag; the estimate always prints; unlimited never prompts), run (the validator script first,
  then the command; PowerShell tool when a harness guard refuses `eval` in Bash), reading Δ (H-10),
  iteration loop (§4 of the fact pack), CI recipe (H-11, both models pinned, `partial` checked first),
  `## Boundary` (the CLI vs this skill, `evals:design` for criteria, `skill-quality:check validate-evals`
  for the other format), `## Next` (→ `/evals:validate` on a failed load; → `/claude-config:unhobble` for
  rules), `## Gotchas`. Every flag, bound, exit code, and the version floor is a four-part drift record;
  none is stated bare.
- Description names the split without the listing gate token (the CLI runs and scores; this skill
  preflights, validates without spending, prices, and reads the delta) and never asserts the command
  exists: preflight's version floor is the gate. The token `resolves in your session` must not appear,
  or the parity script demands a baked row.
- `reference/case-authoring.md` (H-14 checklist), `reference/reading-results.md` (H-10, H-11 JSON
  fields), `reference/ci.md` (recipe plus exit-code table). `evals/evals.json` for the skill.
- **Sanity Check:** `wc -l plugins/evals/skills/plugin-eval/SKILL.md` under 500; `grep -c 'resolves in
  your session' plugins/evals/skills/plugin-eval/SKILL.md` prints 0; `grep -h -E '2\.1\.[0-9]+'
  plugins/evals/skills/plugin-eval/SKILL.md plugins/evals/skills/plugin-eval/reference/*.md | grep -c -v
  -i 'recheck'` prints 0; `check-skill.sh plugins/evals/skills/plugin-eval` reports no FAIL. The live
  preflight check moves to Phase 6, after the manifest keys exist.

### Phase 5: Reopen the recorded decisions and sweep [TODO]

- `plugins/evals/.claude-plugin/plugin.json`: description names the runner and the validator, drops "no
  command executes"; `userConfig` gains `max_cost_usd` (number, default 5, min 0) and `unlimited_cost`
  (boolean, default false); version 0.3.0. `CHANGELOG.md` gains `## [0.3.0]`. `README.md`: the "What it
  deliberately does not do" section becomes what runs where; Configuration documents both keys.
- `skills/design/SKILL.md`: description and "What this skill does NOT do" drop the execution disclaimer;
  plugin targets hand to `claude plugin eval init` (the wrap route for skills); `## Next` → `/evals:plugin-eval`.
  `skills/methodology/SKILL.md`: "not a runner" stays true, the "no marketplace command executes" sentence
  goes; scope boundary points at `evals:plugin-eval`. `skills/design/evals/evals.json:53` expectation text updated.
- `docs/MIGRATION-PLAYBOOK.md` L350-458: the deferral paragraph becomes an adoption record (what shipped,
  the two coexisting formats, the consumer-verify recipe reduced to the validator plus the command), with
  `melodic-software/medley#1418` linked as the tracker that carried the deferral, not closed.
- One dated note each in the four `docs/specs/` files: the routing narrows to `CLAUDE.md` and rules
  (prompt-audit), the runner has shipped so the wrap-as-`case.yaml` condition is met (capability matrix
  ~L201), the criterion now has a runner (write-for-agents brief ~L57), the early-access gate trigger
  has fired (provenance-design-threads ~L107). Each note names "adoption record" and the playbook
  section. Specs are records; the note points, it does not rewrite and does not repeat the phrase it
  retires.
- `node scripts/generate-catalog.mjs` regenerates `docs/CATALOG.md`.
- `plugins/playbooks/skills/skill-authoring/reference/authoring-guidance.md` L221-234 says the command
  "exists in the binary but is undocumented" with a recheck trigger "the Claude Code page documents
  `claude plugin eval`", which has fired: re-fetch the raw docs page, restate the fact, refresh the
  as-of date with the outcome, and bump `playbooks` (patch) with a CHANGELOG line, per
  `docs/conventions/upstream-drift/README.md` "When a trigger fires". The predicate for every audited
  line is "any claim the release invalidates", not the two words.
- Checkbox inventory (≥10 files): the Files affected table rows for this phase, ticked as each lands.
- **Sanity Check:** two arms. Does-not-execute: `grep -rn -i -E 'does not execute evals|no (marketplace
  )?command[^.]*executes' --include=*.md --include=*.json plugins docs --exclude-dir=topics
  --exclude-dir=vendor` prints nothing. Early-access: `grep -rn -i -E 'early[ -]access' --include=*.md
  --include=*.json plugins docs --exclude-dir=topics --exclude-dir=vendor --exclude-dir=specs | grep -v
  -i -E 'shipped|adoption|recheck'` prints nothing (the surviving hits are the playbook adoption record
  and the skill's drift record, each quoting the below-floor error string beside the release that
  retired it; `docs/specs/` are dated records covered by the presence check instead), and `grep -c -i
  'adoption record' <each of the four specs>` ≥ 1; this is the Brief's criterion 6 read as "no file still
  asserts the command is early access", which a quoted error string does not; `scripts/check-changelog-parity.sh --check-bump main` exit 0; `node
  scripts/generate-catalog.mjs --check` (or a re-run plus `git diff --quiet docs/CATALOG.md`) clean;
  `grep -c 'medley#1418' docs/MIGRATION-PLAYBOOK.md` ≥ 1.

### Phase 6: Confirm, run every gate, open the draft PR [TODO]

- Confirming pilot pass against the changed plugin (new skills, rewritten descriptions can flip the
  control case): one full pass under `--max-cost-usd 2`, recorded as a second row set in `pilot.md`;
  the positive Δ must survive it.
- Live preflight check for acceptance criterion 1, through the PowerShell tool:
  `claude -p "/evals:plugin-eval preflight <target>" --plugin-dir plugins/evals` for three targets
  (first confirm which `evals` the session resolves, the worktree copy or the installed 0.2.2, by
  invoking a skill only the worktree copy has; disable the installed copy for the check if both load):
  `plugins/evals` (`target_type: plugin`), a scratchpad directory holding one skill wrapped in a minimal
  `.claude-plugin/plugin.json` (`wrapped-skill`), and `.claude/rules` (`rules`, refused, unhobble named);
  each report must print `cli_version: 2.1.269` and `sandbox_backend: absent`.
- Criterion 4 by the same route: a scratchpad copy of the pilot suite with one case granting `Bash`;
  the preflight transcript must refuse before any CLI invocation, naming the missing backend and the
  cloud route, and the scratchpad holds no `results/` directory afterwards. Criterion 5 (unlimited
  option: estimate shown, no prompt) depends on plugin user config that a `--plugin-dir` session may not
  render; verified by setting the option in the installed plugin's config and invoking, recorded as a
  manual attestation in `verification/preflight.md` with the transcript lines quoted.
- Gates on this machine: `scripts/run-plugin-tests.sh` (new suite), `scripts/check-changed-skills.sh
  main`, `plugins/skill-quality/scripts/check-skill.sh` on both new skills, `scripts/check-skill-leaf-names.sh
  --check`, `scripts/check-changelog-parity.sh --check`, `scripts/check-discriminating-test-skips.sh`,
  `npx --no-install markdownlint-cli2` over the changed files, `overlap.py self-check` and `generate
  --check`, `scripts/affected-tests.sh --explain` (selection only; `--run` is a Linux gate and runs in CI
  after the flip to ready).
- Pre-PR order per `docs/conventions/pre-pr-ordering/README.md`: test, review, stage, simplify, review the
  simplify diff, re-test, verify, open. `/review:quality-gate` then `/verification:confirm` against the
  Brief's acceptance criteria, then `/source-control:pull-request create` as a draft with the body
  contract: `No related issue: adoption of a shipped CLI surface; medley#1418 carried the deferral`,
  Summary, Fix, Verification (the pilot table), Related (`melodic-software/medley#1418`, the Q12 cloud
  follow-up, the untested Bash-granting cases). Ask whether to open the Q12 issue; file nothing without a
  yes.
- **Sanity Check:** every gate above exit 0; the confirming JSON has `partial == false` and at least one
  `cases[].aggregates.delta > 0`; the three preflight transcripts contain the expected `target_type`
  lines; the pilot cost total in `pilot.md` is at most 8 USD; `gh pr view --json isDraft` prints `true`; the PR body contains `No related issue:`
  and the four section headings.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Validator in Bash plus awk (the shape of `check-evals-quality.sh`) | the repo's awk frontmatter reader has no sequence path, so the `case.yaml` grader list where duplicate names arise is unreadable, and a WARN-at-exit-0 on unparsed input green-lights what was not read | a shared shell YAML reader with block-sequence support lands in the repo |
| Validator as `.mjs` on `js-yaml` | full YAML, but `js-yaml` is a transitive dev dependency of this repo, absent in a consumer's checkout where `${CLAUDE_PLUGIN_ROOT}` scripts run | the plugin gains a declared Node runtime dependency |
| One skill (`evals:plugin-eval` with a `validate` action) instead of two | "validate my eval cases" is a distinct trigger; the validator is the no-spend entry point a user reaches before ever running | the listing-budget check reports the `evals` plugin over budget after both descriptions land |
| Pilot on a larger plugin (`skill-quality`) | more surface to grade but Bash-granting cases are refused here; `evals` is read-only by nature and the plugin under improvement | the pilot's Δ stays at zero after two reruns and the methodology reference has no distinctive term to grade |
| A new `plugin-evals` plugin | rejected in the interview: duplicates the doctrine home and collides with two community names | none; the Brief forecloses it |
| Bake the listing gate phrase into `evals:plugin-eval` and flip the store flags | the gate token is defined as a condition on the model's skill listing; a shell subcommand never enters it, and writing the token before the flags flip turns the parity check red across the parallel wave | the native-references convention extends the gate to CLI subcommands, or `overlap.py` learns a CLI provenance class |
| Guide skill named `evals:run` | the bundled `run` skill already has a store row and `overlap.py detect` pairs by leaf name | the bundled `run` skill is retired upstream |
| Bump `package.json` to 2.1.269 | the pin only feeds cloud-bootstrap's marketplace registration; dependabot owns the bump | a script or CI lane starts running `node_modules/.bin/claude plugin eval` |

### Test strategy

- Test boundaries: the validator CLI (`validate-cases.py <dir>`, newly introduced; output-based tests
  through temp-dir fixtures, no doubles); the two `evals/evals.json` suites (skill-creator format, newly
  introduced, gated by `check-changed-skills.sh`); the pilot suite (upstream format, run through the CLI).
  The skill bodies have no unit test; their observable is the invocation in acceptance criteria 1, 4, 5,
  verified by hand in Phase 6 and recorded in `verification/`.
- Red first: eight fixture tests fail before the script exists; each named finding line and exit code is
  the assertion.
- Edge cases: `case.yaml` plus `prompt.md` in one case (precedence), a grader with `arm: with-only`, an
  `env` key without the `EVAL_` prefix, a `weight: 0`, a frontmatter with an anchor or multi-line scalar
  (fail-closed path), a flow mapping target (`{ source: file, path: x }`).
- Existing tests: none change; no tracked fixture tree exists for the orphan or lane gates to see.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Δ is zero: the base model already answers eval questions | Med | High | grade only terms the reference files supply; the control case proves the indicator works; fallback in Phase 2 |
| A rate limit mid-suite reads as a regression | Low | Med | check `cases[].arms.with[].error` before scores; rerun the affected case |
| Cost overrun | Low | Low | `--max-cost-usd 5`; at most two reruns; estimate printed first |
| The markdown-format hook rewrites `prompt.md` bodies | Med | Low | keep bodies lint-clean; diff after the hook; `graders/*.md` bodies are prose |
| `check-changed-skills.sh` fails on a new skill (evals, invocation key, description length) | Med | Low | Phase 3 and 4 checklists carry all three; `check-skill.sh` in the sanity check |
| The harness guard blocks the pilot command in Bash | Certain here | Low | PowerShell tool; recorded as a Gotcha with a drift record |
| Spec edits read as rewriting history | Low | Med | one dated note per spec; the adoption record lives in the playbook |
| Every command fact is one-day-old, corroboration-pending | Certain | Med | drift records with the next-release trigger; the pilot run is the live verification |

## Blast radius

MEDIUM. Twenty or more files across two plugins (`evals` in full, `playbooks` for one fired recheck
trigger), six docs, one store, and `.gitignore`; two new
convention-bearing skills; a paid side effect (the pilot run) bounded by a ceiling; no shared hook or CI
change; everything reverts with git. Stress-test triggers matched: a new skill that composes other skills
and spends money; a multi-step change on one-day-old behavior.

## Stress-test summary

Two fresh-context passes, both verified against the tree before any fix was applied.

Plan reviewer (1 critical, 3 important, 5 suggestions): the acceptance grep was unsatisfiable because
drift records and the adoption record must quote the below-floor error string; the listing gate token
written before the store flags flipped would have turned the parity check red across the parallel wave;
the pilot measured a plugin the later phases change; the preflight check had no invocation route and no
wrapped-skill target; `--max-cost-usd` bounds one invocation, not a phase. Fixed: split verification
arms, registry-only row with no baked phrase, confirming pass in Phase 6, `claude -p --plugin-dir`
route with three targets, per-pass ceiling and a total.

Devil's advocate (3 critical, 3 high, 5 medium, 2 low): the methodology references distill public
Anthropic pages so the without-arm may already know them (a cloud session is no fallback for that); the
awk frontmatter reader has no sequence path, so the one place duplicate grader names arise was unreadable
and a WARN at exit 0 green-lit unread input; a fourth spec carries a hyphenated `early-access`; a rate
limit passes the pilot check while inflating Δ; the default threshold makes exit 1 meaningless; the
`authoring-guidance.md` recheck trigger has fired; the portability scanners skip `*/evals/*` and so this
whole plugin. Fixed: term-uniqueness probe and the indicator-form fallback, Python stdlib validator that
fails closed, `early[ -]access` plus the fourth spec, null-error and no-skipped-graders assertions,
`--threshold 0.8` with the JSON as oracle, the trigger honored with a `playbooks` patch bump, the scanner
gap recorded as a follow-up. Residual: a repo-original term must reach `last_message` for a regex to
see it; acceptance criteria 4 and 5 rest on unrecorded CLI behavior and are verified by invocation.

## Execution shape

Sequential 1 → 2 (main session: judgment, spend, PowerShell tool), then Wave A in parallel: Phase 3
(validator), Phase 4 (runner skill), Phase 5 (sweep), then Phase 6 in the main session.

| Phase | Files | Overlaps with |
|---|---|---|
| 1 | records.json, NATIVE-SURFACES.md, .gitignore, design-resolution.md, PLAN.md | none |
| 2 | plugins/evals/evals/**, verification/pilot.md | none |
| 3 | plugins/evals/skills/validate/** | none |
| 4 | plugins/evals/skills/plugin-eval/** | none |
| 5 | evals plugin.json, CHANGELOG, README, design/, methodology/, MIGRATION-PLAYBOOK, four specs, CATALOG, three playbooks files | none |
| 6 | verification/pilot.md, PR | 2 (pilot.md, sequential anyway) |

Dependencies: 1 → every skill body (the store row precedes any reference); 2 → 3 (the pilot suite is
the validator's live fixture) and → 4 (the Δ evidence shapes the reading section); 3 → 4 only by the
script path, fixed here as `plugins/evals/skills/validate/scripts/validate-cases.py`; 5 names `evals:plugin-eval`
and `evals:validate`, fixed here; 6 after all.

Recommended: Wave A as three sub-agent workers (opus) in one message, roughly 900 LOC of independent
work; cost about three times a sequential pass in tokens. Sequential fallback: 3 → 4 → 5 in the main
session if any worker reports a scope-fence violation or cannot complete.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | small edits citing the store shape; commits |
| 2 | main session | spends money; PowerShell tool; judgment on Δ |
| 3 | sub-agent worker | file-disjoint, test-driven script work |
| 4 | sub-agent worker | file-disjoint, one skill directory |
| 5 | sub-agent worker | mechanical sweep with a fixed inventory |
| 6 | main session | gates, review, verification, PR |

| Agent | Phase | ALLOWED files | LOC |
|---|---|---|---|
| A1 | 3 | `plugins/evals/skills/validate/**` | ~500 |
| A2 | 4 | `plugins/evals/skills/plugin-eval/**` | ~350 |
| A3 | 5 | the Phase 5 inventory rows only | ~150 |

A3's ALLOWED list is the Phase 5 inventory: the `evals` manifest, CHANGELOG, README, `design/` and
`methodology/` skill files, the playbook section, the four specs, `docs/CATALOG.md`, and the three
`playbooks` files. A3 is told that the advisory skill-reference hook will flag `/evals:plugin-eval` and
`/evals:validate` as absent while A1 and A2 are still writing them; that is expected, not a divergence.

Each agent FORBIDDEN: any file outside its list, `PLAN.md`, the other agents' directories, staging or
committing. Each reports: work items done, per-criterion sanity verdict, LOC delta.

```text
DIVERGENCE ESCALATION (mandatory): if reality diverges from this brief —
a precondition fails, a file/symbol named here is absent or different than
described, scope is blocked, or a design question arises mid-task — STOP.
Do not improvise, fix forward, or expand scope. Report to the orchestrator:
what you found, what the brief expected, and the exact state of your work
(files touched, edits applied / not applied). Await a revised brief.
```

## Open questions

- Q12 (Brief): Bash-granting and Write-granting cases stay untested here; named in the PR body.
- Whether to open the Q12 GitHub issue: asked at PR time, filed only on a yes.
- Whether to persist the standards inference (`.claude/standards.yaml` → `docs/conventions/`): asked at
  approval, written only on a yes.
- Repo defect found, out of scope: `scripts/check-shell-portability.sh` and `check-skill-portability.sh`
  skip `*/evals/*`, which the plugin named `evals` matches wholesale, so nothing under it has ever been
  scanned. Named in the PR body as a follow-up; a work item only on the user's say-so.
- Whether `--trust-plugin` trust persists past a run for the whole repository: unrecorded; carried as a
  Gotcha and in `pilot.md`.

## Handoff to implementation

### User-approval gates

- Pilot spend: passes of at most 2 USD each, three in Phase 2 and one in Phase 6, 8 USD in total; plan
  approval is the spend approval unless the user names another number.
- Phase 2 fallback: if no positive Δ survives two reruns, stop and route to the cloud follow-up
  `[FALLBACK — confirm or override]`.
- Phase 5 spec notes: each `docs/specs/` file gets one dated pointer note rather than a rewrite.
- Phase 6: the Q12 issue and the standards persistence are asked, never assumed.

### Execution shape ([EXEC-SHAPE] tagged)

- Skill names `plugin-eval` and `validate` under `evals`; validator in Python 3 standard library, failing
  closed on unparsed input, tested with temp-dir fixtures; `playbooks` patch bump for the fired recheck
  trigger; pilot target
  `evals:methodology` with the three cases above; version 0.3.0; store row registry-only, no listing
  phrase baked; the acceptance observable split into a does-not-execute grep and an early-access grep
  that tolerates dated adoption and drift records, both excluding `docs/topics/` (the Brief quotes the
  phrases it forbids) and `vendor/`; a confirming pilot pass in Phase 6; a pilot budget of 8 USD in
  passes of 2; Wave A routing as tabled.

### Mechanical work

- One commit per green phase through `/source-control:commit`; PLAN.md phase tags advance in the same
  commit; `verification/pilot.md` rides the Phase 2 commit.
- Every file write through the Write or Edit tool (guardrails block shell redirects); plain git commands
  only; the pilot command through the PowerShell tool. The worktree guard refuses any Bash command
  containing the bare word `eval`, including a commit whose message says `plugin eval`; the hyphenated
  path `plugin-eval` passes. Write commit subjects with `evals` or `plugin-eval`, or commit through the
  PowerShell tool.
- Pre-PR order per `docs/conventions/pre-pr-ordering/README.md`; close-out per `/planning:plan close-out`
  before merge (paste the plan and verification into the PR, prune the contract slice with a pointer).
