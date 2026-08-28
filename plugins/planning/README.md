# planning

A Claude Code plugin for the **pre-implementation planning pipeline**: everything
between a rough idea and approved, executable work. Eleven pipeline skills covering
charting a too-big, foggy effort as a decision map, divergence, product intent, the
engineering contract, contract validation, hand-off of a decision another person
holds, goal authoring, design exploration, the design→plan gate, adversarial review,
and the implementation plan itself, plus a re-runnable `setup` action that settles
where artifacts land in the consuming repo.

| Skill | Stage | What it does |
|---|---|---|
| `/planning:wayfind` | Chart | Charts a too-big-AND-foggy effort as a shared decision map on the work-item tracker, then works its frontier one decision at a time, routing each to the right skill until the fog clears and a Brief / PRD / PLAN can be handed onward. Upstream of the whole pipeline. |
| `/planning:brainstorm` | Diverge | Turns a rough problem into codebase-grounded candidate approaches ordered cheapest→most ambitious; the user reacts, then work routes onward scoped. |
| `/planning:prd` | Product intent | Produces a Product Requirements Document (problem, users, success metrics) in three tiers (one-pager, consumer-feature, B2B-internal) with a synthesize path and a review mode. |
| `/planning:interview` | Engineering contract | Locks a task contract (goal, constraints, acceptance criteria, named assumptions) into a PLAN.md Brief, synthesizing when intent is clear, running frontier-rounds Q&A when it isn't, or interviewing relentlessly on request. |
| `/planning:audit-answers` | Contract validation | Independent adversarial validation of a completed `/planning:interview`'s answers, over any filled ledger, hand-answered or auto-accepted. Fresh-context validators re-examine each answer with its rationale withheld and return one verdict per answer: `confirmed`, `challenged`, or `reclassified`. Only the challenged and reclassified answers, plus every user-reserved decision, return as real human questions. Open branches are accept-filled first, holding the never-auto floor. |
| `/planning:questionnaire` | Person hand-off | Turns a decision another person holds into a discovery questionnaire delivered async. It interviews the user about the send only (recipient, what's needed back), writes the document to the topic's memory slice, and leaves delivery out-of-band. |
| `/planning:draft-goal-condition` | Goal authoring | Crafts a paste-ready `/goal` completion condition from a stated intent. It reads the current official `/goal` docs live for the condition shape and character limit (nothing hardcoded), drafts a transcript-demonstrable condition, and proves it fits the limit with a deterministic character counter instead of model guesswork, with a branch that builds a checkable condition for goals no metric can measure; a lever-fit gate routes interval-shaped, cloud/sessionless, orchestration-only, and multi-window / multi-ticket work elsewhere. Standalone. |
| `/planning:design` | Design space | Explores types, contracts, module boundaries, and package topology through collaborative discussion rounds, producing capability-matrix / type-inventory / design-threads / topology artifacts; its `handoff` action delegates to `/planning:design-handoff`. |
| `/planning:design-handoff` | Design→plan gate | Gates a finished design for `/planning:plan`. The gate is a binary check that every `design-threads.md` thread is RESOLVED, directional, or TAGGED-DEFERRED. Then it packages the plan-ready summary and resume prompt, or FAILs and routes back to `/planning:design`. |
| `/planning:devils-advocate` | Adversarial review | Stress-tests plans via assumption extraction, evidence checks, failure scenarios, and operational-gotcha sweeps. Every finding evidence-backed, never generic warnings. An `incumbent` mode turns the same lens on the status quo: an Alternatives Sweep that stress-tests keeping an incumbent tool/approach against alternatives (native > official > vetted ladder, coupling priced, KEEP / MIGRATE / RESEARCH verdict), exploring the incumbent first-hand in a fresh sub-agent. |
| `/planning:plan` | Implementation plan | Produces a structured plan (goal, approach, test strategy, blast radius, parallelism analysis, tagged unilateral decisions) with a mandatory fresh-context stress-test and a user approval gate, persisted to PLAN.md. |
| `/planning:setup` | Configuration | `check` inspects the topic-docs seam and standards index read-only; `apply` interviews the consumer and persists the tracked `.claude/topic-docs.yaml` concern file that governs where every pipeline skill writes its per-topic artifacts, and bootstraps the standards index (idempotent; re-run to reconfigure). |

The pipeline composes end-to-end. `wayfind` charts the fog upstream when an effort
is too big to hold at once, then `brainstorm → prd → interview → design →
design-handoff → plan` with `devils-advocate` attacking the plan before
approval, while `/domain-driven-design:curate-language` is invoked whenever
those workflows resolve vocabulary, when the `domain-driven-design` plugin is
installed; without it, resolved terms are recorded in the design artifacts
themselves. Every skill also works standalone.

## Works in any repo

- **Reads your conventions, assumes none.** Project rules, naming conventions,
  review checklists, domain-vocabulary files, and commit policy come from your own
  project's `CLAUDE.md` and rules; where none exist, the skills apply standard
  engineering defaults.
- **Graceful degrade.** Adjacent capabilities are invoked when installed:
  codebase exploration and external research (`discovery`), test-design guidance
  (`tdd`), prototyping (`prototype`), and session handoff (`session-flow`).
  Missing plugins get inline guidance; no step blocks.
- **Self-contained assets.** Templates and reference files ship inside the plugin;
  planning artifacts land per the topic-docs convention. Contract documents go in
  `<contract_dir>/<topic-slug>/` (default `docs/topics/`) on the task branch, working
  memory in the self-ignoring `<memory_dir>/<topic-slug>/` (default `.work/`). Never
  in plugin-internal paths.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install planning@<marketplace>
```

## Configuration

Where artifacts land is governed by the marketplace-wide **topic-docs convention**
(`docs/conventions/topic-docs/` in this repository): contract documents (`PRD.md`,
`PLAN.md`, `design/`) go to `<contract_dir>/<topic-slug>/` (default `docs/topics/`) on
the task branch; working memory (checklists, baselines, scratch) goes to the
self-ignoring `<memory_dir>/<topic-slug>/` (default `.work/`). Run
`/planning:setup check` to inspect the effective values read-only, or
`/planning:setup apply` to interview and persist the tracked
concern file `.claude/topic-docs.yaml` (`contract_dir`, `memory_dir`,
`contract_tier: branch | local`); absent keys mean those documented defaults.

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `use_ask_user_question` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_USE_ASK_USER_QUESTION` | When enabled, the planning skills' question rounds (interview, prd, design, plan) render a round of up to 4 independent questions through the AskUserQuestion tool instead of inline prose. Default: inline prose (dictation-friendly). |
| `use_emoji_question_markers` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_USE_EMOJI_QUESTION_MARKERS` | When enabled, each inline interview round question leads with a ❓ anchor on its Q<N> line and its 'My recommendation:' line leads with ➡️. Purely presentational. Q<N> numbering stays the functional handle, and persisted artifacts (ledger, register, Brief) never carry the emoji. Default: plain text. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure planning@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install planning@<marketplace> -s <scope> --config use_ask_user_question=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior — a check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "planning@<marketplace>": {
         "options": {
           "use_ask_user_question": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
<!-- ai-slop-ignore-end -->

## License

MIT (SPDX-License-Identifier: MIT).
