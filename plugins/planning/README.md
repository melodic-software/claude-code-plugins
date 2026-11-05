# planning

A Claude Code plugin for the **pre-implementation planning pipeline**: everything
between a rough idea and approved, executable work. Eleven pipeline skills covering
charting a too-big, foggy effort as a map of decision items, divergence, product intent, the
engineering contract, contract validation, hand-off of a decision another person
holds, goal authoring, design exploration, the design→plan gate, adversarial review,
and the implementation plan itself, plus a re-runnable `setup` action that settles
where artifacts land in the consuming repo.

| Skill | Stage | What it does |
|---|---|---|
| `/planning:wayfind` | Chart | Charts a too-big-AND-foggy effort as a shared map of decision items on the work-item tracker, then works its frontier one decision at a time, routing each to the right skill until the fog clears and the map closes to `/planning:prd`, `/work-items:decompose` or `/work-items:work`. An escalation from an interview that outgrew one session, never the first step. |
| `/planning:brainstorm` | Diverge | Turns a rough problem into codebase-grounded candidate approaches ordered cheapest→most ambitious; the user reacts, then work routes onward scoped. |
| `/planning:prd` | Product intent | Produces a Product Requirements Document (problem, users, success metrics) in three tiers (one-pager, consumer-feature, B2B-internal) with a synthesize path and a review mode. Acceptance-criteria capture asks once about missing unwanted-behavior and state-driven cases (skipped and reported unexamined on the `synthesize` path). |
| `/planning:interview` | Engineering Brief | Locks the task's Brief (goal, constraints, acceptance criteria, named assumptions) into PLAN.md, synthesizing when intent is clear, running frontier-rounds Q&A when it isn't, or interviewing relentlessly on request. Acceptance-criteria capture asks once about missing unwanted-behavior and state-driven cases, and emits EARS-tagged criteria when the team's convention selects that format. The `surface` option can render rounds on a local page the session watches. The `product` action interviews a product idea against product principles and ends in a verdict. |
| `/planning:audit-answers` | Contract validation | Independent adversarial validation of a completed `/planning:interview`'s answers, over any filled ledger, hand-answered or auto-accepted. Fresh-context validators re-examine each answer with its rationale withheld and return one verdict per answer: `confirmed`, `challenged`, or `reclassified`. Only the challenged and reclassified answers, plus every user-reserved decision, return as real human questions. Open branches are accept-filled first, holding the never-auto floor. |
| `/planning:questionnaire` | Person hand-off | Turns a decision another person holds into a discovery questionnaire delivered async. It interviews the user about the send only (recipient, what's needed back), writes the document to the topic's memory slice, and leaves delivery out-of-band. |
| `/planning:draft-goal-condition` | Goal authoring | Crafts a paste-ready `/goal` completion condition from a stated intent. It reads the current official `/goal` docs live for the condition shape and character limit (nothing hardcoded), drafts a transcript-demonstrable condition, and proves it fits the limit with a deterministic character counter instead of model guesswork, with a branch that builds a checkable condition for goals no metric can measure; a lever-fit gate routes interval-shaped, cloud/sessionless, orchestration-only, and multi-window / multi-ticket work elsewhere. Standalone. |
| `/planning:design` | Design space | Explores types, contracts, module boundaries, and package topology through collaborative discussion rounds, producing capability-matrix / type-inventory / design-threads / topology artifacts; its `handoff` action delegates to `/planning:design-handoff`. Its `data`, `integration`, and `system` artifacts are typed: each carries a `scope` + `dialect` label and a fenced block in the dialect the `diagram_dialect` convention key resolves to (mermaid `erDiagram` or DBML for data; mermaid `sequenceDiagram` plus an OpenAPI 3.1 sketch for integration; a LikeC4 or C4-PlantUML container view for system, and no C4 view at all when that key is unset). `library` and `module` emit no typed artifact. |
| `/planning:design-handoff` | Design→plan gate | Gates a finished design for `/planning:plan`. The gate is a binary check that every `design-threads.md` thread is RESOLVED, directional, or TAGGED-DEFERRED. Then it packages the plan-ready summary and resume prompt, or FAILs and routes back to `/planning:design`. On PASS and FAIL alike it also emits an advisory six-dimension coverage table (what, how, where, who, when, why) that never contributes to the verdict; uncovered dimensions ride along in the handoff summary and the resume prompt. |
| `/planning:devils-advocate` | Adversarial review | Stress-tests plans via assumption extraction, evidence checks, failure scenarios, and operational-gotcha sweeps. Every finding evidence-backed, never generic warnings. An `incumbent` mode turns the same lens on the status quo: an Alternatives Sweep that stress-tests keeping an incumbent tool/approach against alternatives (native > official > vetted ladder, coupling priced, KEEP / MIGRATE / RESEARCH verdict), exploring the incumbent first-hand in a fresh sub-agent. |
| `/planning:plan` | Implementation plan | Produces a structured plan (goal, approach, test strategy, blast radius, parallelism analysis, tagged unilateral decisions) with a fresh-context `plan-reviewer` stress-test, on by default and set per mode by `plan_stress_test`, and a user approval gate, persisted to PLAN.md. |
| `/planning:setup` | Configuration | `check` inspects the standards index read-only; `apply` interviews the consumer and bootstraps the standards index (idempotent; re-run to reconfigure). |

The pipeline composes end-to-end. `wayfind` charts the fog upstream when an effort
is too big to hold at once, then `brainstorm → interview → design →
design-handoff → plan`, the interview calling `prd` when product intent is unsettled, with `devils-advocate` attacking the plan before
approval, while `/domain-driven-design:curate-language` is invoked whenever
those workflows resolve vocabulary, when the `domain-driven-design` plugin is
enabled; without it, resolved terms are recorded in the design artifacts
themselves. Every skill also works standalone.

## Workflows

- **`/planning:plan-panel`** (`workflows/plan-panel.js`). A multi-angle plan
  panel that `/planning:plan` launches, opt-in, for a hard or wide plan:
  one planner per angle (MVP-first, risk-first, reuse-first and
  testability-first by default), independent judges that score every draft on
  goal fit, blast radius, test strategy and reversibility, and one synthesizer
  that builds the plan from the winner and grafts runner-up ideas. Its `args`
  carry `task` (required; without it the run dispatches nothing), `context`,
  `angles`, `judges` (default 3), `roles` and `maxConcurrent` (default 4).
  `roles` is the map `/multi-agent:route all` prints. Without it, built-in fallbacks run planners
  on `opus` at `medium` effort and judges on `opus` at `high`, and the
  synthesizer inherits the session model at `high`. It returns the plan, the
  scores, the grafted ideas, the dissent and every draft; the synthesized plan goes
  through the skill's reviewer and approval gate. When the Workflow tool is
  absent, `/planning:plan` formulates the single plan as before.

## Works in any repo

- **Reads your conventions, assumes none.** Project rules, naming conventions,
  review checklists, domain-vocabulary files, and commit policy come from your own
  project's `CLAUDE.md` and rules; where none exist, the skills apply standard
  engineering defaults.
- **Graceful degrade.** Adjacent capabilities are invoked when enabled:
  codebase exploration and external research (`discovery`), test-design guidance
  (`tdd`), prototyping (`prototype`), decision recording (`architecture`), and
  session handoff (`session-flow`).
  Missing plugins get inline guidance; no step blocks.
- **Self-contained assets.** Templates and reference files ship inside the plugin;
  planning artifacts land in the self-ignoring memory slice
  `<memory_dir>/<topic-slug>/` (default `.work/`). Never in plugin-internal paths.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install planning@melodic-software
```

## Configuration

Where artifacts land is set by the plugin's lifecycle artifact protocol
(`reference/artifact-protocol.md`): every working artifact (`PRD.md`, `PLAN.md`,
`design/`, checklists, baselines, scratch) goes to the self-ignoring
`<memory_dir>/<topic-slug>/` (default `.work/`) and is never committed. Durable
content is published to the pull request body and the linked issue. Run
`/planning:setup check` to inspect the standards index read-only, or
`/planning:setup apply` to bootstrap it.

The **format acceptance criteria are written in** is a separate, optional team-shared
choice. `/planning:interview` and `/planning:prd` read
`acceptance_criteria_format` from `<home>/authoring-formats/README.md`, where
`<home>` is the convention home bound by the pointer line in your root instruction
file. `ears` tags every emitted criterion with one of five bracketed patterns
(`ubiquitous`, `event-driven`, `state-driven`, `unwanted-behavior`,
`optional-feature`); `free-text` is the default and emits prose criteria untagged,
exactly as before. Every failure to resolve degrades to `free-text` with the cause
named, whether that is no pointer line, no such document, no such key, or an
unrecognized value, so a repo that declares nothing sees no change in output.

### Option details

**`surface`.** A value other than `terminal` or `page` falls back to `terminal`.

**`plan_store`.** A repository sets it for everyone with `plan_store: local` or `plan_store: tracker`
in `docs/conventions/planning.yaml` (schema: `schemas/planning.schema.json`), which wins over this
option. Any other value resolves `local`. `tracker` needs the work-items plugin and a claimed item.

**`plan_reader`.** How much of an approved plan reaches the work item and the pull request paste:
`step-by-step` (default) the whole plan, `standard` the design plus a phase outline, `guardrails`
the design alone, each reduced copy also keeping the Brief. A reduced depth publishes a derived file and
leaves PLAN.md whole. `--reader <depth>` on `/planning:plan` overrides it for one run, and the plan
records the depth it published at so a later close-out keeps it. A repository sets it for everyone
with the `plan_reader` key in `docs/conventions/planning.yaml`, which wins over this option. A value
outside the three, `--reader` included, is named and that layer is dropped: a valid higher layer
still wins, otherwise the plan publishes `step-by-step`, never a lower layer's value.
`/planning:setup apply plan_reader=<value>` writes the repository file.

**`phase_order`.** Decides the order of a plan's phases after the build technique is chosen.
`composed` removes dead code the change touches first (a bug fix skips this), then builds the
integration slice, then the riskiest remaining unknown, then scaffold, then the remaining features.
`subtraction-first` runs dead-code removal, then scaffold, then features. `riskiest-first` puts the
step whose failure would invalidate the most later work first. A repository sets it for everyone
with the `phase_order` key in `docs/conventions/planning.yaml`, which wins over this option. A value
outside the three is named and that layer is dropped; with no valid layer left the plan uses
`composed`. `/planning:setup apply phase_order=<value>` writes the repository file. All keys and
layers: [`reference/config.md`](reference/config.md).

**`scaffold_stubs`.** Off by default. When on, `/planning:design` lists each new file the design
needs with the signatures it will declare, and `/planning:plan` turns that list into one stub phase
right after the dead-code removal step (first when there is none). Stub bodies use the language's
ordinary not-implemented form, and a stub phase that leaves the build or tests red declares it with
a `**Planned breakage:**` line. A repository sets it for everyone with `scaffold_stubs: true` or
`scaffold_stubs: false` (bare booleans; a quoted `"true"` is invalid and that layer is dropped) in
`docs/conventions/planning.yaml`, which wins over this option.
`/planning:setup apply scaffold_stubs=true` writes it.

**`use_emoji_question_markers`.** The anchors are on by default. On the page surface they sit on
the question title and the Recommendation heading; the terminal line they lead is
`My recommendation:`. Q<N> numbering stays the functional handle, and persisted artifacts (ledger,
register, Brief) never carry the emoji. A user instruction against emoji wins over this option, and
the page is then started with `--emoji-markers false` so it matches the terminal.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `surface` | string | `"terminal"` | Where /planning:interview asks its rounds: terminal (default, inline) or page (a local 127.0.0.1 page the session watches). Unset: terminal, and the interview names the other available surfaces in one line. |
| `question_pacing` | string | `"round"` | How /planning:interview asks a frontier: round (default, every ready question in one message) or single (one per message, largest blast radius first). Asking for the other pacing in a session overrides it there; a repository's planning.yaml in its convention home overrides this value. |
| `use_ask_user_question` | boolean | `false` | When enabled, the planning skills' question rounds (interview, prd, design, plan) render a round of independent questions that fits one AskUserQuestion call instead of inline prose. Default: inline prose (dictation-friendly). |
| `use_emoji_question_markers` | boolean | `true` | When on, each interview round question leads with a ❓ anchor on its Q<N> line and its My recommendation line leads with ➡️, in the terminal and on the page surface. Purely presentational: persisted artifacts never carry the emoji. Default: on; turn off for plain text. |
| `shared_session_open_browser` | boolean | `true` | When on, starting a /planning:interview shared session opens the owner's page in the default browser. Turn off to open it yourself. Default: on. |
| `tunnel_hostname` | string | *(none)* | Hostname of a named Cloudflare tunnel for /planning:interview shared sessions (such as interview.example.com), so the guest link survives a restart. One session serves it at a time; others get a quick tunnel. Empty (default): a quick tunnel, whose link changes on restart. Setup: shared/README.md. |
| `tunnel_token_file` | string | *(none)* | Absolute path, or one starting with ~/, of a file holding the named tunnel's token, readable only by you; cloudflared runs from it. Used only when tunnel_hostname is set. Default: empty. |
| `tunnel_api_token_file` | string | *(none)* | Absolute path, or one starting with ~/, of a file holding a Cloudflare API token with Cloudflare One Connector: cloudflared Write (it can change every tunnel in the account), readable only by you; sessions check connectors and route the tunnel to their port. Empty: port 8765. See shared/README.md. |
| `plan_store` | string | `"local"` | Where /planning:plan keeps an approved plan: local (default, PLAN.md in the memory slice only) or tracker (also posted as one comment on the claimed work item). A repository's docs/conventions/planning.yaml plan_store key overrides this value. |
| `plan_reader` | string | `"step-by-step"` | How much of an approved plan /planning:plan publishes: step-by-step (default, the whole plan), standard (Brief, design, phase outline) or guardrails (Brief and design). A --reader argument overrides it per run; a repository's docs/conventions/planning.yaml plan_reader key overrides this value. |
| `phase_order` | string | `"composed"` | How /planning:plan orders phases: composed (default: dead-code removal, integration slice, riskiest unknown, scaffold, features), subtraction-first (removal, scaffold, features) or riskiest-first. A repository's docs/conventions/planning.yaml phase_order key overrides this value. |
| `scaffold_stubs` | boolean | `false` | When on, /planning:design hands off the stub files and signatures a change needs, and /planning:plan puts one stub phase right after dead-code removal (first when there is none). Default: off. A repository's docs/conventions/planning.yaml scaffold_stubs key overrides this value. |
| `time_units` | boolean | `false` | When on, the planning skills may state an estimate or budget of work in hours, days or weeks; when off they use the work_size levels instead. Practice cadence and measurement windows are not affected. Default: off. A repository's docs/conventions/planning.yaml time_units key overrides this value. |
| `medium` | string | `"auto"` | Where planning views go. auto (default): plan, brainstorm and design views go to a private Artifact, kept by the publish gate for a non-public repository or credential-shaped record; PRD and interview views stay local. terminal: no page; file: local; artifact: publish anyway; hosted = artifact. |

### How to set these

Set the options above for `planning@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

As of 2026-11-04. Recheck trigger: one of these sections moves, or a Claude Code
release note changes how plugin options are set or stored.

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
