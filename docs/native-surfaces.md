# Native surfaces registry

Generated view over the native-overlap store. The block between the markers below is rendered from
`docs/native-surfaces/records.json` by
`plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py generate` and kept in sync by CI.
**Never hand-edit it.** Verdicts, evidence, and recheck triggers are edited in the store; this
file is output.

Every verdict here is a human's. Rows are recorded per overlap between a native Claude Code surface
and a component in this repository, and each one carries the observable event that obliges
re-deriving it. Availability is never asserted: an observation record says what was seen, where,
and when. See [`docs/conventions/native-references/`](conventions/native-references/README.md).

<!-- native-surfaces:start -->

## Summary

| Lane | Rows | Baked | Verdicts |
|---|---|---|---|
| Built-in CLI commands | 3 | 2 | complementary 3 |
| Bundled skills | 13 | 12 | complementary 12, defer 1 |
| Plugin-backed built-ins | 1 | 1 | complementary 1 |
| Session-provided skills (observation-only) | 1 | 0 | defer 1 |
| First-party marketplace plugins | 2 | 2 | complementary 2 |

## Built-in CLI commands

### `export` → `session-flow:clean-stop`

- **Verdict:** `complementary`: No component duplicates /export and none may invoke it: built-ins are user-invoked only, and the command is confirmed unavailable headless. clean-stop, handoff (prompt-only path), and retro instead suggest that the user run it at session-end moments, because transcripts are retention-swept and the conversation otherwise has no durable artifact. The native surface does the exporting; the skills only name the moment and a destination convention (<memory_dir>/exports/). Verdict recorded per the user-approved export-session-flow Brief (PR #3355).
- **Native surface:** `export` (built-in command; markers: none)
- **Our component:** `session-flow:clean-stop` (skill)
- **Evidence:**
  - probed on the live v2.1.241 binary 2026-08-24: `claude --bare -p "/export <path>"` returned `/export isn't available in this environment.` and wrote no file, so the command is an interactive-terminal surface
  - documented at code.claude.com/docs/en/commands.md: /export renders the current conversation as plain text to clipboard or a file (optional filename argument), no format or redaction flags
  - output written to user paths sits outside the cleanupPeriodDays retention sweep (path-scoped to ~/.claude), which is the durability property the suggestions exist for
  - suggestion sites: plugins/session-flow/skills/clean-stop/SKILL.md (durability sweep), handoff/SKILL.md (prompt-only close), retro/SKILL.md (post-chain-coverage offer); all body text, presence-gated with the canonical token, none baked into a description or Boundary section
- **Observation:** live-roster: probed on the live v2.1.241 binary in a Linux container (headless form unavailable; interactive form documented but not observed here); one environment, one day (2026-08-24)
- **Recheck trigger:** a Claude Code release note or docs change adds an /export format/redaction flag, a headless or programmatic form, or an official conversation-sharing surface; any of these reopens whether suggestion-only is still the right integration shape (verified 2026-08-24)
- **Baked:** description phrase no · Boundary section no

### `plugin eval` → `evals:plugin-eval`

- **Verdict:** `complementary`: The CLI runs and scores: `claude plugin eval <target>` loads the plugin, runs every case in a with-plugin arm and a no-plugin baseline arm, grades each run, and reports WITH, W/OUT, and the delta. evals:plugin-eval is the guided practice around that command, which the CLI does not ship: a preflight that reports the CLI version against the floor, whether a sandbox backend exists on this machine, and the target type (plugin, wrapped skill, wrapped agent, hooks as advisory; CLAUDE.md and rules refused because the run strips them by design); static validation of the case files with no model call; a cost estimate from cases x runs x arms and a ceiling from plugin user config passed as --max-cost-usd; and a delta-first reading with the iteration loop. Neither replaces the other: the skill never grades, and the command never preflights, prices, or reads. The skill's Boundary section names the command; no listing phrase is baked, because the native-references gate token is a condition on the model's skill listing, and a CLI subcommand never enters that listing, so the skill gates on the CLI itself (preflight's version floor) instead. The gated marker rests on two switches: below the floor the binary prints an early-access refusal, and a server-side switch prints an unavailable refusal that nothing local restores.
- **Native surface:** `plugin eval` (built-in command; markers: gated)
- **Our component:** `evals:plugin-eval` (skill)
- **Evidence:**
  - `claude plugin eval --help` at 2.1.269 (read 2026-09-11): 'Run eval cases (<eval dir>/**/case.yaml or prompt.md + graders/*.md; the eval dir is evals/ unless --eval-dir or the manifest says otherwise) against a plugin and report scored results. Target is a path, a plugin name, or a plugin@marketplace id: installed and skills-dir plugins both resolve (and add a no-plugin baseline arm)'; `--ablation` defaults to with-without whenever a plugin resolves and reports the score delta, and under it graders marked with-only, including `tool_used: Skill`, are a plugin-fired indicator rather than part of the score
  - the same help text: `--max-cost-usd` is an optional hard ceiling checked before each run launches (exit 2 with partial results when hit; paid graders skipped on the breaching run while free graders still score it); `--trust-plugin` answers the first-run trust prompt for CI; `--threshold` defaults to 1.0; `--allow-tools` is the operator grant for Bash, Write, Edit, WebFetch, and mcp__*; `init` takes only --bare, --eval-dir, and -i
  - https://code.claude.com/docs/en/plugin-evals.md (the raw variant; read 2026-09-11) documents the same flag set, the case layout, the exit codes 0/1/2/130/143, and the aggregate-result.json fields; the raw page matched `--help` exactly where a summarizer over the rendered page had fabricated a flag table
  - gate basis: the command shipped in Claude Code 2.1.269 (anthropics/claude-code, 2026-09-11); below that floor the binary prints `plugin eval is currently in early access`, and a server-side switch prints `plugin eval is currently unavailable`, which no local setting restores
  - the docs page: the run strips user settings, hooks, CLAUDE.md, MCP servers, other plugins, memory, and skills, so a rules or CLAUDE.md target has nothing to measure; native Windows has no sandbox backend, so a case granting Bash, Write, or Edit is refused rather than run unconfined, with WSL2 named for Windows and bubblewrap plus socat for Linux
  - the docs page: the case format (`prompt.md` plus `graders/*.md`, or `case.yaml` with `schema_version: "1.1"`) is not the skill-creator `evals/evals.json` format this marketplace's skills carry, so the two coexist and `skill-quality:check validate-evals` keeps the other one
  - our planned description: preflight, validate without spending, price, and read the delta for a `claude plugin eval` run; the CLI runs and scores, this skill guides the practice around it (shipped as `plugins/evals/skills/plugin-eval` in melodic-software/claude-code-plugins#4154)
  - `plugin eval` is absent from the 2.1.232 and 2.1.251 extractions the sibling rows rest on; absence from an extraction is a statement about the extraction, and the command postdates both
- **Observation:** extraction: `claude plugin eval --help` from the installed CLI at 2.1.269 (`claude --version` prints `2.1.269 (Claude Code)`), read live in the session on 2026-09-11; a targeted observation of one subcommand's help text, not a re-extraction of the binary's roster (2026-09-11)
- **Recheck trigger:** a Claude Code release after 2.1.269 changes the plugin eval flag set, the case schema version, the exit codes, the ablation exclusion rule for with-only and `tool_used: Skill` graders, the early-access or unavailable gate strings, or the sandbox backend list; or the command or its docs page gains a preflight, validate-only, dry-run, or cost-estimate mode that makes any part of evals:plugin-eval redundant (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `skill-doctor` → `claude-ops:audit-skill-visibility`

- **Verdict:** `complementary`: The sibling doctor row's split, narrowed to the surface that now owns the question. Built-in /skill-doctor is a one-shot report of what each loaded skill costs in context and how often it is used, so unused ones can be turned off. audit-skill-visibility answers why a skill is unseen: it reconciles three usage sources (native ~/.claude.json counters, its own JSONL store, OTEL) under a max-across-sources rule, computes an observed horizon and withholds every verdict the span cannot support, diagnoses reachability causes, and analyses listing-budget starvation. It disables nothing by contract. This row is separate from the doctor row rather than folded into it because the two surfaces carry different gates: /doctor answers to DISABLE_DOCTOR_COMMAND, /skill-doctor to a minimum version and to feature-flag fetching, so a session can resolve either, both, or neither, and each routing line needs its own presence gate.
- **Native surface:** `skill-doctor` (built-in command; markers: gated)
- **Our component:** `claude-ops:audit-skill-visibility` (skill)
- **Evidence:**
  - upstream commit d7dbd9a09f59775726ed14bbea8fc9dfdff62f7b in anthropics/claude-code (2026-09-04) added the `## 2.1.261` CHANGELOG heading and, under it, `Added /skill-doctor to show which loaded skills go unused and what they cost in context, so you can prune them`; read from the commit diff, not from the rendered changelog page
  - https://code.claude.com/docs/en/commands.md carries a /skill-doctor row in the all-commands table, and that row does NOT carry the bold `[Skill](/docs/en/skills#bundled-skills).` prefix the same table puts on /doctor, /run, /run-skill-generator and /simplify; that prefix is how the table marks a bundled skill, so this row is classed builtin-command rather than bundled-skill (read 2026-09-07)
  - the same table row and https://code.claude.com/docs/en/skills.md ('Find unused skills') both state that /skill-doctor requires Claude Code v2.1.252 or later and is unavailable in sessions that skip feature-flag fetching, and the skills page adds that it answers `Skill usage reports are not available on this connection.` over Remote Control; that is the gate this row records, and it is not doctor's
  - the version the surface was announced in and the version it is documented to require disagree upstream: the CHANGELOG lands it at 2.1.261 while commands.md and skills.md say v2.1.252 or later, so no shipped routing line in this repository states a version for it (read 2026-09-07)
  - our description: audit whether each installed skill is actually VISIBLE to the model; reconciles native counters, a JSONL store, and OTEL; withholds every verdict the data cannot support; read-only, never disables, deletes, or edits a skill
  - our description's Not-for clause, the Purpose section, and the SKILL.md Scope boundary table each name /skill-doctor behind its own `resolves in your session` gate, separate from the /doctor gate beside it
- **Observation:** upstream-source: d7dbd9a09f59775726ed14bbea8fc9dfdff62f7b, the anthropics/claude-code commit that added the 2.1.261 CHANGELOG entry naming /skill-doctor, plus the commands.md and skills.md pages read the same day. Not an extraction and not a live roster: this container runs 2.1.258, below the release that announced the surface, so nothing here observed the command itself. (2026-09-07)
- **Recheck trigger:** a Claude Code release note or docs change removes /skill-doctor, folds its report back into /doctor, gives its all-commands row the bundled-skill marker (which moves this row to the bundled-skill lane and changes which switch disables it), changes its version or feature-flag gate, or gives it a multi-source reconciliation or observation-horizon discipline of its own (verified 2026-09-07)
- **Baked:** description phrase yes · Boundary section no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

## Bundled skills

### `claude-api` → `claude-config:audit-instructions`

- **Verdict:** `complementary`: Composite posture, decided at the ClaudeDevs cost-performance adoption interview: wrap or point to the bundled subcommand where it fits the use case, and run our own processes where they fit, rather than routing one way on paper. The bundled skill's prompt-audit subcommand is the vendor's apply-sweep over the working directory's whole prompt surface, application code included; audit-instructions is a standing report-only audit of locally-owned Claude Code instruction surfaces with the versioned I-catalog, target-model scoping, and deterministic pre-scans. ADR-0028 already composes both: run the vendor procedure per model change, feed recurring gap shapes back into the catalog. The app-code surface stays with the bundled skill (scope widening rejected at the same interview).
- **Native surface:** `claude-api` (bundled skill; markers: none)
- **Our component:** `claude-config:audit-instructions` (skill)
- **Evidence:**
  - binary extraction 2026-09-09 (claude.exe 2.1.263): registerClaudeApiSkill present; subcommand array cost-optimize, migrate, managed-agents-onboard, prompt-audit, upgrade, build-eval, hillclimb
  - platform docs claude-api-skill page (fetched 2026-09-09): 'The skill comes bundled with Claude Code and is also available in the open-source Anthropic skills repository'
  - hillclimb and build-eval are bundled-only: absent from anthropics/skills HEAD 41bbe19 (2026-09-03) and from the skill's docs page
  - executed composition precedent: docs/specs/prompt-audit-skills-2026-09.md (fleet-wide prompt-audit run, 805 findings applied) + ADR-0028 (repeats per model change; findings are edits, not criteria)
  - verdict recorded from the owner's interview answers in docs/upstream/claudedevs-cost-performance.md Lane M and Lane T2, 2026-09-10
- **Observation:** extraction: extracted from binary 2.1.263 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (registerClaudeApiSkill string plus subcommand array; bundled shared/evals/eval-hillclimb.md extracted and read); bulk registrar enumeration was broken at this build, so this row's evidence is the targeted extraction, not the inventory JSON (2026-09-09)
- **Recheck trigger:** a Claude Code release changes the bundled claude-api skill's subcommand set, or the anthropics/skills repo or the platform claude-api-skill docs page gains hillclimb/build-eval (which also fires the docs/upstream/claudedevs-cost-performance.md hillclimb row) (verified 2026-09-10)
- **Baked:** description phrase no · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `claude-api` → `evals:methodology`

- **Verdict:** `complementary`: Different jobs on the same object. The bundled skill's hillclimb subcommand consumes an eval suite and searches model and effort for the cheapest configuration that holds the target (train/test split, one change per round, held-out scoring), and build-eval scaffolds the suite it needs; both run evals and change configuration. evals:methodology is knowledge about designing the suite (criteria, anatomy, grading, effort as an axis) and runs nothing. The two chain: design the suite here, hand it to the search. Recorded when the effort-axis note citing hillclimb landed in the methodology reference.
- **Native surface:** `claude-api` (bundled skill; markers: none)
- **Our component:** `evals:methodology` (skill)
- **Evidence:**
  - binary extraction 2026-09-09 (claude.exe 2.1.263): subcommand array includes build-eval and hillclimb; bundled shared/evals/eval-hillclimb.md read end to end (train/test split, one proposal per round, held-out scoring)
  - hillclimb and build-eval absent from anthropics/skills HEAD 41bbe19 (2026-09-03) and from the platform claude-api-skill docs page
  - our description: 'Knowledge (WHY/WHAT of eval design), not a runner; ... for running and scoring a plugin's suite against a no-plugin baseline use /evals:plugin-eval'
  - reference/eval-design.md 'Effort as an eval axis' cites the subcommand behind the presence gate
- **Observation:** extraction: extracted from binary 2.1.263 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (subcommand array; bundled shared/evals/eval-hillclimb.md extracted and read); bulk registrar enumeration was broken at this build, so this row's evidence is the targeted extraction, not the inventory JSON (2026-09-09)
- **Recheck trigger:** a Claude Code release changes the bundled claude-api skill's subcommand set, or the public anthropics/skills repo or the docs page gains hillclimb/build-eval (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `claude-api` → `playbooks:fable-5`

- **Verdict:** `complementary`: The playbook's chapters defer every current fact (model ID, price, beta boundary, parameter shape) to the bundled claude-api skill by standing rule, and its API prompt-caching chapter names cost-optimize as the automation for the cost levers it describes. The bundled skill resolves live facts and acts (prompt-audit, cost-optimize, hillclimb edit prompts and configuration when asked); the playbook is operating doctrine and mechanisms that outlive any one price, and performs no work. Neither replaces the other.
- **Native surface:** `claude-api` (bundled skill; markers: none)
- **Our component:** `playbooks:fable-5` (skill)
- **Evidence:**
  - binary extraction 2026-09-09 (claude.exe 2.1.263): registerClaudeApiSkill present; subcommand array cost-optimize, migrate, managed-agents-onboard, prompt-audit, upgrade, build-eval, hillclimb
  - platform docs claude-api-skill page (fetched 2026-09-09): bundled with Claude Code and published in the open-source skills repository
  - reference/model-adaptation/fable-5-1.md standing rule: 'this chapter carries no model ID, price, or limit. Resolve the current details through the claude-api skill at the moment of use'
  - reference/prompt-caching.md 'Automation' bullet cites cost-optimize behind the presence gate
- **Observation:** extraction: extracted from binary 2.1.263 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (registerClaudeApiSkill string plus subcommand array); bulk registrar enumeration was broken at this build, so this row's evidence is the targeted extraction, not the inventory JSON (2026-09-09)
- **Recheck trigger:** a Claude Code release changes the bundled claude-api skill's subcommand set or moves it between bundled and marketplace distribution (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `code-review` → `review:code-review`

- **Verdict:** `complementary`: Same object, different invocation surface. The bundled skill is a session-driven review of the current diff or a named PR, with mutating flags (--fix writes the working tree, --comment posts to the PR). review:code-review is a non-interactive CI lane a reusable workflow invokes for one pull request, deliberately scoped out of security when a security lane exists. Neither replaces the other: a CI lane cannot be typed into a session, and the session surface has no workflow contract.
- **Native surface:** `code-review` (bundled skill; markers: none)
- **Our component:** `review:code-review` (skill)
- **Evidence:**
  - `code-review` present in the extraction as bundled-skill
  - aliases: review
  - native description: Review the current diff or a PR for bugs and cleanups
  - our description: CI code-review lane for a GitHub pull request. High-signal correctness and maintainability findings only, scoped out of security when a security lane exists
  - the review plugin already documents this overlap organically in plugins/review/skills/quality-gate/context/pr.md's Boundary section, naming the bundled command, the marketplace plugin, and the managed service as three distinct surfaces
- **Observation:** extraction: extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded, counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release changes the bundled `code-review` skill's roster entry, its `review` alias, or its invocation mode. The alias was re-pointed at 2.1.220 and the alias-under-shadowing fix landed at 2.1.233, so this pair has moved twice in one quarter (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `design` → `prototype:explore-directions`

- **Verdict:** `complementary`: explore-directions offers the editable design-canvas Artifact as an explicit alternative to its HTML mockup substrate when the bundled skill is listed with the canvas description, invoking it only on the user's choice and keeping the mockup as the default. The canvas persists under the user's account; the mockup is thrown away once the winning-variant key is captured. Same surface as the visualize row, sibling component; the Boundary section states the split and the presence check, and the description's presence phrasing predates the registry and carries no gate token.
- **Native surface:** `design` (bundled skill; markers: gated)
- **Our component:** `prototype:explore-directions` (skill)
- **Evidence:**
  - our description: 'or, where the bundled design skill is available, an editable design-canvas Artifact'; the body's design-canvas subsection offers the canvas before building and the Boundary section states the split, the mutation gate, and the presence check
  - string search of the installed binary v2.1.263 (2026-09-11): the canvas skill registers model-invocable and user-invocable with no disableModelInvocation, enabled by a first-party-context check, a rollout flag that defaults on, and an Artifact tool whose schema carries capabilities; a second same-named Claude Design hub registration carries disableModelInvocation true behind an allow_design_sync setting (detail in the sibling visualize row and plugins/prototype/skills/explore-directions/reference/bundled-design.md)
  - commands page (2026-09-11) carries a /design row labeled Skill describing the canvas and its gates (artifacts availability, v2.1.234+); the changelog names no design-family surface through v2.1.268
  - prior: binary extraction v2.1.251 (2026-08-31) registered the canvas skill research-preview gated with no model-invocation gate; the 2.1.263 registration matches except that the rollout flag now defaults on
- **Observation:** extraction: targeted string search of the installed binary v2.1.263 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (both design registrations read from the bundle strings), refreshing the v2.1.251 extraction (2026-09-11)
- **Recheck trigger:** a Claude Code release adds a model-invocation gate to the canvas skill, changes either design registration's enablement or subcommand set, merges the two registrations, a release note first names a design-family surface, or the commands-page row stops describing the canvas (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes

### `design` → `visualization:visualize`

- **Verdict:** `complementary`: visualize's form matrix routes hand-tweakable visual layouts (UI mockups, posters, one-pagers) to the bundled design canvas when it is listed with the canvas description, offered as an explicit alternative and invoked only on the user's choice, with the shadowing check and never-mention-when-absent rule its catalog spoke documents. The canvas is a persistent, versioned, shareable Artifact; this skill's page paths are throwaway or plain-static. The Boundary section states the split, the mutation gate, and the presence check; the catalog spoke carries the surface facts.
- **Native surface:** `design` (bundled skill; markers: gated)
- **Our component:** `visualization:visualize` (skill)
- **Evidence:**
  - our SKILL.md step 2: 'a design canvas. Route to a design-canvas capability (the bundled design skill), when available'; the Boundary section states the split and the presence check
  - catalog spoke plugins/visualization/skills/visualize/context/decision-matrix.md carries the canvas surface facts with their own verified-on line
  - string search of the installed binary v2.1.263 (2026-09-11): the canvas skill registers model-invocable and user-invocable (menu line 'Draft a design on a canvas Artifact, editable where saving is enabled (Claude Design preview)'; description 'Create a design canvas...'; argument hint '[what to design]'; no disableModelInvocation; enabled by a first-party-context check, a rollout flag that defaults on, and an Artifact tool whose schema carries capabilities); it is listed to the model with the canvas description in a first-party session on that build
  - string search of the same binary: a second bundled registration named design is a Claude Design hub (menu line 'Work with Claude Design (claude.ai/design): create, import, export, sync, login') with disableModelInvocation true, enabled only behind an allow_design_sync setting, a policy gate, and a feature flag; a local design consent|revoke command beside it; so the listed description is the presence check
  - commands page (2026-09-11) carries a /design row labeled Skill describing the canvas (artboards on one canvas published as an artifact running a research preview of Claude Design's editor; requires artifacts availability and v2.1.234+); the artifacts page's 'Draft a design canvas' shows /design <brief>; the changelog names no design-family surface through v2.1.268
  - prior: binary extraction v2.1.251 (2026-08-31) registered the canvas skill with a /design dispatch table and no model-invocation gate, and the rollout flag defaulted off at v2.1.234; the 2.1.263 registration matches except that the flag now defaults on
- **Observation:** extraction: targeted string search of the installed binary v2.1.263 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (both design registrations read from the bundle strings), refreshing the v2.1.251 extraction (2026-09-11)
- **Recheck trigger:** a Claude Code release adds a model-invocation gate to the canvas skill, changes either design registration's enablement or subcommand set, merges the two registrations, a release note first names a design-family surface, or the commands-page row stops describing the canvas (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes

### `design-sync` → `visualization:visualize`

- **Verdict:** `defer`: Deliberately undetermined. The design-sync family (design-sync skill with disableModelInvocation, hidden design-consent/design-revoke commands managing a durable agent-access grant, design-login credential flow, DesignSync tool) is registered in the binary but documented nowhere through v2.1.251, and no operator of this marketplace uses claude.ai/design design-system projects. Real enough to record next to the canvas integration it ships beside; too thin to rule on, and design-system sync is publishing, not visualization, so no integration text ships anywhere.
- **Native surface:** `design-sync` (bundled skill; markers: hidden, gated)
- **Our component:** `visualization:visualize` (skill)
- **Evidence:**
  - binary extraction v2.1.251 (2026-08-31): design-sync registered with disableModelInvocation true; design-consent/design-revoke registered as hidden commands ('Grant/Revoke Claude agent access to your Design projects'); design-login flow strings present
  - docs and changelog through v2.1.251 carry none of the four names (checked 2026-08-31)
  - no claude.ai/design usage among this marketplace's operators (user-confirmed 2026-09-01)
- **Observation:** extraction: extracted from binary v2.1.251 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (design-family registrations read from the bundle strings) (2026-08-31)
- **Recheck trigger:** a Claude Code release documents any of design-sync/design-consent/design-revoke/design-login, or an operator of this marketplace adopts claude.ai/design design-system projects (verified 2026-09-01)
- **Baked:** description phrase no · Boundary section no

### `doctor` → `claude-ops:audit-install-state`

- **Verdict:** `complementary`: Bundled `doctor` is the quick native health-and-fix pass over an installation, and it offers to fix, which puts it outside the read-only contract audit-install-state holds. audit-install-state is the deep read-only inventory of the install tree: every file classified, product-managed retention separated from genuinely unmanaged state, filename schemes resolved before any liveness check, and a deliberate-or-experimental state detected before anything is called stale. Prefer the native pass for a fast check; ours when the question is what is actually in the tree and what nothing manages.
- **Native surface:** `doctor` (bundled skill; markers: gated)
- **Our component:** `claude-ops:audit-install-state` (skill)
- **Evidence:**
  - `doctor` present in the extraction as bundled-skill
  - markers: gated
  - aliases: checkup
  - native description: Health-check your setup and fix issues: installation, unused extensions, duplicated or bloated memory files, slow hooks, updates, permissions
  - the native surface offers to fix; audit-install-state is report-only by contract and never writes to the target tree
  - shared listing budget measured at ~13.0x over the documented 8,000-char default across 153 listing-eligible skills (check-listing-budget.sh, 2026-08-23), so the baked phrase is the best available routing surface, not a guaranteed one
- **Observation:** extraction: extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded, counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release changes `/doctor`'s status as a bundled skill or its gating switch. It became a bundled skill at 2.1.205, which retargeted DISABLE_DOCTOR_COMMAND, and it is the one bundled skill `disableBundledSkills` does not remove (verified 2026-08-23)
- **Baked:** description phrase yes · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `doctor` → `claude-ops:audit-performance`

- **Verdict:** `complementary`: Same native surface, a different one of our lanes. audit-performance is a timed diagnostic capture taken at the moment something feels slow: CLI version, retention-sweep health, a timed stat-walk standing in for the product's own sweep cost, session and plugin-fleet counts, and a process census, all interpreted against a bundled known-issues reference. Bundled `doctor` reports health and offers fixes; it does not capture a timed slowness profile. Registry-row only: the routing line for this pair lives on audit-install-state, which owns the shared surface description for the plugin.
- **Native surface:** `doctor` (bundled skill; markers: gated)
- **Our component:** `claude-ops:audit-performance` (skill)
- **Evidence:**
  - `doctor` present in the extraction as bundled-skill
  - markers: gated
  - native description: Health-check your setup and fix issues: installation, unused extensions, duplicated or bloated memory files, slow hooks, updates, permissions
  - our description: read-only slowness-diagnostic capture run AT THE MOMENT the machine or a session feels slow, before restarting or deleting anything
- **Observation:** extraction: extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded, counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release gives `/doctor` a timed or profiling mode, or changes its status as a bundled skill (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `doctor` → `claude-ops:audit-skill-visibility`

- **Verdict:** `complementary`: Same native surface as the two sibling rows, a third of our lanes. Bundled `doctor` ships a one-shot check (its Check 1) that groups unused skills, MCP servers, and plugins against their context cost, labels each group with a token-savings estimate, and offers to disable the selected groups. audit-skill-visibility answers a different question, why a skill is unseen: it reconciles three usage sources (native ~/.claude.json counters, its own JSONL store, OTEL) under a max-across-sources rule, computes an observed horizon and withholds every verdict the span cannot support, diagnoses reachability causes, and analyses listing-budget starvation. It disables nothing by contract. The skill's own description and Scope boundary already route the one-shot unused-versus-context-cost question to the native surface; this row records that routing in the store rather than replacing it.
- **Native surface:** `doctor` (bundled skill; markers: gated)
- **Our component:** `claude-ops:audit-skill-visibility` (skill)
- **Evidence:**
  - `doctor` present in the 2026-08-23 extraction as bundled-skill (markers: gated; aliases: checkup), per the two sibling rows
  - the shipped doctor skill carries a check titled 'Check 1: unused skills, MCP servers, and plugins' whose prompt groups unused components, labels each group with a benefit estimate ('37 unused skills, saves ~2.2k est. tokens/session'), and applies only the groups the user selects; confirmed by string search of the installed v2.1.252 binary on 2026-08-31
  - our description: audit whether each installed skill is actually VISIBLE to the model; reconciles native counters, a JSONL store, and OTEL; withholds every verdict the data cannot support; read-only, never disables, deletes, or edits a skill
  - our description's Not-for clause and the SKILL.md Scope boundary table both already name the native surface ('Claude Code ships that in /doctor and the Stats tab') with no store row behind them until this one; a prose disclaimer without a store row is the drift this registry exists to catch
  - recheck trigger fired 2026-09-04 and is discharged as of 2026-09-07: /skill-doctor now has its own row in this store, pinned to the upstream commit that added it, so this row is scoped back to /doctor alone and no longer stands in for two surfaces
  - this row's routing survives the split: the /doctor row of https://code.claude.com/docs/en/commands.md still credits the bundled doctor skill with finding 'unused skills, MCP servers, and plugins versus their context cost' inside its setup checkup, so the deferral recorded here is to a surface that still does the job (read 2026-09-07)
- **Observation:** extraction: targeted string search of the installed binary v2.1.252 (doctor Check 1 strings confirmed; a spot observation over the sibling rows' full v2.1.232 extraction, not a re-extraction) (2026-08-31)
- **Recheck trigger:** a Claude Code release changes doctor's unused-components check (Check 1's grouping, its disable offer, or its benefit estimate), gives it a multi-source reconciliation or observation-horizon discipline, or changes /doctor's status as a bundled skill or its gating switch (verified 2026-09-11)
- **Baked:** description phrase yes · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `run` → `testing:run-e2e`

- **Verdict:** `complementary`: The bundled skill answers 'did this change work when I ran the app'; run-e2e drives named UI and API flows, captures evidence (screenshots, responses, logs), and carries a non-UI smoke playbook for libraries, MCP servers, hooks, and scripts, none of which have an app to launch. Prefer the native surface for the quick look; ours where the verification has to be reproducible or the target is not an app.
- **Native surface:** `run` (bundled skill; markers: none)
- **Our component:** `testing:run-e2e` (skill)
- **Evidence:**
  - `run` present in the extraction as bundled-skill
  - native description: Launch this project's app to see your change working
  - our description: End-to-end live app verification. Check prerequisites, start the app, drive UI/API flows, and capture evidence; includes a non-UI smoke-test playbook
  - the non-UI smoke lane has no native counterpart in this extraction
- **Observation:** extraction: extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded, counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release changes the bundled `run` skill's roster entry or invocation mode, or gives it an evidence-capture or non-app target mode (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `simplify` → `code-tidying:batch-simplify`

- **Verdict:** `complementary`: Scale is the whole difference. The bundled skill handles the change in front of it; batch-simplify fans the same job across a time- or branch-scoped window of changed files, grouped by ecosystem and dependency order, for the catch-up case after a multi-session sprint. Its description already sends single-file cleanup to the native surface.
- **Native surface:** `simplify` (bundled skill; markers: none)
- **Our component:** `code-tidying:batch-simplify` (skill)
- **Evidence:**
  - `simplify` present in the extraction as bundled-skill
  - native description: Clean up the changed code without changing behavior
  - our description already carries `Skip for single-file cleanup. Use /simplify instead`
  - seeded rationale: same cleanup job at batch scale across many files
- **Observation:** extraction: extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded, counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release gives the bundled `simplify` skill a time-window argument form, a repository mode, or ecosystem grouping (the multi-file half of this trigger fired by 2026-09-11: the skill accepts a path or PR reference target, so the remaining distinction is the sweep discipline, recorded in the skill's context/bundled-simplify.md) (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `simplify` → `code-tidying:tidy`

- **Verdict:** `complementary`: Different trigger, not a different job. The bundled skill refines the code a change already touched; tidy proactively hunts unfiled structural drift across a rotated, glob-scoped lane and ships one structure-only PR per invocation. tidy's own description already routes current-diff work away to the native surface, which is the routing this row records rather than replaces.
- **Native surface:** `simplify` (bundled skill; markers: none)
- **Our component:** `code-tidying:tidy` (skill)
- **Evidence:**
  - `simplify` present in the extraction as bundled-skill
  - native description: Clean up the changed code without changing behavior
  - our description already carries `Skip when: /simplify refines the current diff`
  - seeded rationale: both clean up code without changing behavior
- **Observation:** extraction: extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded, counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release adds, removes, or changes the invocation mode of the bundled `simplify` skill, or the skill gains a lane-scoped mode that overlaps tidy's proactive hunt (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

## Plugin-backed built-ins

### `security-review` → `review:security-review`

- **Verdict:** `complementary`: The native side is not a bundled skill at all. The extraction reports it under `plugin_backed`, backed by the `security-review` plugin, and it runs in-session over the change at hand. review:security-review is the CI lane a reusable workflow invokes for a pull request, targeting logic, trust-boundary, and Actions findings static analysis misses. Reading the wrong extraction key is the failure this row exists to prevent: under `builtin_commands` the surface looks absent.
- **Native surface:** `security-review` (plugin-backed built-in; markers: none)
- **Our component:** `review:security-review` (skill)
- **Evidence:**
  - `security-review` present in the extraction as plugin-backed-builtin
  - the extraction's `plugin_backed` map reports {"security-review": "security-review"}; the name appears in neither `builtin_commands` nor `bundled_skills`
  - our description: CI security-review lane for a GitHub pull request. Logic, trust-boundary, and Actions security findings static analysis misses
- **Observation:** extraction: extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded, counts are floors) (2026-08-23)
- **Recheck trigger:** an extraction stops reporting `security-review` under `plugin_backed`: it moves into the bundled-skill or built-in-command lane, or its backing plugin name changes (re-verified 2026-09-11: the installed 2.1.263 binary registers it plugin-backed and the commands page gives the row no Skill label; the skill's reference/bundled-security-review.md carries the record) (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

## Session-provided skills (observation-only)

### `morning` → `claude-ops:morning-brief`

- **Verdict:** `defer`: Undetermined, and deliberately so. `morning` was observed in a session roster, not in any binary extraction, so the only evidence available is one environment's roster on one day, not a basis for a routing line shipped to every consumer. The overlap is real enough to record and too thin to rule on: nothing is known about what the session-provided skill reads, whether it is gh-based, or whether it exists outside the surface it was seen on. Observation-only, never baked, until an in-session capture protocol exists.
- **Native surface:** `morning` (session-provided skill; markers: none)
- **Our component:** `claude-ops:morning-brief` (skill)
- **Evidence:**
  - `morning` is absent from this extraction. Absence from the extraction is a statement about the extraction, not the product
  - observed in this repository's cloud session roster on 2026-08-23, alongside other session-provided skills (docx, pdf, pptx, xlsx, design, artifact-*) that the local-CLI bundled roster does not carry
  - our description: prints the operator's read-only morning view for the current GitHub repo in one pass: queue-label counts, merge-ready PRs, parked decisions, loop-lane telemetry freshness
- **Observation:** live-roster: observed in a Claude Code cloud session's own skill roster; one environment, one day, no second observation (2026-08-23)
- **Recheck trigger:** an in-session roster capture protocol lands and can observe this surface repeatably, or `morning` appears in a binary extraction's bundled-skill set (verified 2026-08-23)
- **Baked:** description phrase no · Boundary section no

## First-party marketplace plugins

### `playground` → `prototype:explore-directions`

- **Verdict:** `complementary`: Both produce a browser page with switchable controls, which is why the pair needs a recorded boundary: explore-directions varies YOUR PROJECT'S own UI (real header, real data, real routes) so you can pick a direction and throw the rest away, while a playground explores an arbitrary parameter space and hands back a prompt. Its description now routes the explorer shape to the playground skill via the playgrounds wrapper.
- **Native surface:** `playground` (first-party marketplace plugin; markers: none)
- **Our component:** `prototype:explore-directions` (skill)
- **Evidence:**
  - upstream SKILL.md read at commit ed404106fcd80ba98ecb7c851e531dcb626d13b7: 'especially when the input space is large, visual, or structural and hard to express as plain text'
  - our description: builds throwaway UI variations, several radically different visual layouts on one route, switchable from a floating control bar
  - the baked routing clause carries the marketplace parity token so fleet parity traces it to this row
  - corpus slice: 27-resource verified map (2026-08-31)
- **Observation:** upstream-source: anthropics/claude-plugins-official at commit ed404106fcd80ba98ecb7c851e531dcb626d13b7 (HEAD of main, re-verified by fetch 2026-09-01) (2026-09-01)
- **Recheck trigger:** the upstream repository's default branch moves past the pinned commit with changes under plugins/playground, or the playground plugin is renamed, removed, or absorbed into the CLI as a bundled skill (verified 2026-09-01)
- **Baked:** description phrase yes · Boundary section no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `playground` → `visualization:visualize`

- **Verdict:** `complementary`: visualize decides the best visual FORM for conversation content and renders it; the first-party playground skill builds an interactive parameter explorer whose output returns as a prompt. The shapes meet only at 'show me this visually', so visualize's Boundary section routes explorer-shaped requests out (to the playground skill, or the playgrounds wrapper which owns install uplift and cloud delivery) and keeps every static form for itself.
- **Native surface:** `playground` (first-party marketplace plugin; markers: none)
- **Our component:** `visualization:visualize` (skill)
- **Evidence:**
  - upstream SKILL.md (plugins/playground/skills/playground/SKILL.md) read at commit ed404106fcd80ba98ecb7c851e531dcb626d13b7: 'interactive controls on one side, a live preview on the other, and a prompt output at the bottom with a copy button'
  - our description: decide the best visual FORM and MEDIUM for what is in the conversation right now, then render it
  - the wrapper plugin `playgrounds` declares the cross-marketplace dependency and carries the install uplift, so the Boundary route has a landing surface in this marketplace
  - corpus slice: 27-resource verified map of the announcement article, plugin source, and implicated docs (2026-08-31)
- **Observation:** upstream-source: anthropics/claude-plugins-official at commit ed404106fcd80ba98ecb7c851e531dcb626d13b7 (HEAD of main, re-verified by fetch 2026-09-01) (2026-09-01)
- **Recheck trigger:** the upstream repository's default branch moves past the pinned commit with changes under plugins/playground, or the playground plugin is renamed, removed, or absorbed into the CLI as a bundled skill (verified 2026-09-01)
- **Baked:** description phrase no · Boundary section yes

<!-- native-surfaces:end -->
