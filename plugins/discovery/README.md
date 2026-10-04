# discovery

A Claude Code plugin for **structured discovery before changes**. Understand what
IS (the local codebase), what SHOULD BE (current external sources), and what WAS
and why (the reasoning behind a past decision) before any code is written. Those
three skills sit on the evidence-substrate axis and **dispatch a purpose-built
subagent by default**, so the reading stays out of the main conversation;
`blindspot` serves the USER's understanding rather than the agent's.

| Skill | Axis | What it does |
|---|---|---|
| `/discovery:explore` | Local | Six-dimension codebase exploration, code reading, git history, project structure, test discovery, build config, environment, persisting an `EXPLORE.md` index plus sidecars. Dispatches `discovery:explorer` by default. |
| `/discovery:research` | External | Corpus enumeration, then three chained research phases (broad → targeted + falsification → preferred sources) with per-claim source tiers, independent-corroborator ratios, a recency gate, a coverage ledger, and a binary outcome gate before presenting. Dispatches `discovery:researcher` by default. |
| `/discovery:research-deep` | External, tiered | Dispatcher that routes deep research to the heaviest isolated tier available, the `discovery:research-sweep` workflow, a `discovery:researcher` subagent, or inline as last resort, with a multi-topic check that fans one `discovery:researcher` out per separable topic. Runs in main context itself, the only place both the `Workflow` tool (absent from every non-fork subagent) and a dependable `Agent` spawn are guaranteed. |
| `/discovery:trace-intent` | Historical | Reconstructs why a thing was built the way it was, from evidence outside the code: review discussion, tickets, long-form documents. Grades every claim on an intent-evidence tier (Direct / Supported / Inferred / Speculative / Unknown), cites each one with a source-reliability note, and reports what it could not find in a coverage map. Dispatches `discovery:intent-tracer` by default. |
| `/discovery:blindspot` | Local, user-facing | Surfaces the USER's unknown-unknowns before they work in unfamiliar territory (a codebase area or a domain vocabulary), emitting blindspot cards and coaching one improved prompt. Deliverable is the user's understanding, not `EXPLORE.md`. |

`discovery:report` is the return-contract skill: not user-invocable, and the canonical copy that `implementation` and `plugin-quality` mirror byte-identically. No discovery agent preloads it: each agent's own `Return exactly this` section is its whole return shape.

| Agent | Dispatched by | What it does |
|---|---|---|
| `discovery:explorer` | `/discovery:explore` | Runs the six dimensions in a fresh context, loads path-scoped project rules explicitly, writes the artifact set, returns a bounded summary and a file pointer. |
| `discovery:researcher` | `/discovery:research`, `/discovery:research-deep` | Runs the full research discipline in a fresh context, writes the artifact set and coverage ledger, returns a file pointer plus a verification request. |
| `discovery:research-verifier` | `/discovery:research`, `/discovery:research-deep` | Read-only. Grades a research artifact's verifier-owned outcome-gate rows in a fresh context and returns the `verification:` line the parent writes into `RESEARCH.md`. |
| `discovery:sweep-worker` | the `discovery:research-sweep` workflow | Runs one workflow stage with web search and fetch only, so no stage that reads untrusted pages holds a shell or file access. Inherits the model and pins no effort; the workflow passes both from the role map. |
| `discovery:intent-tracer` | `/discovery:trace-intent` | Investigates the resolvable evidence categories in a fresh context, grades each claim on the intent-evidence tier, writes the artifact set, and returns a file pointer plus a verification request. |

| Workflow | Launched by | What it does |
|---|---|---|
| `/discovery:research-sweep` (`workflows/research-sweep.js`) | `/discovery:research-deep` Tier 1 | Sweeps sources for one question by angle, deep-reads the best of them, has three independent skeptics try to refute each load-bearing claim (a claim survives on a majority; a skeptic that could not check counts as unverified, not refuted), runs a completeness critic, and returns findings with citations, source tier, date and consensus counts, plus dissent and unverified claims. `args`: `question` (required; without it nothing runs), `angles`, `sources`, `roles` (the map `/multi-agent:route all research` prints; without it, fan-out stages run on `opus`), `maxConcurrent` (default 4) and `artifactPath`. Every stage runs as `discovery:sweep-worker`, reads only public http(s) URLs, and receives page-derived text as fenced JSON. It writes no files: `research-deep` writes `RESEARCH.md` from the result. |

The three artifact-persisting skills (`/discovery:explore`, `/discovery:research`,
`/discovery:trace-intent`) persist handoff artifacts (`EXPLORE.md` / `RESEARCH.md`
/ `INTENT.md`) so a fresh session can resume planning from the artifact alone.
Each is **always an index**, with content in sibling sidecars carrying a
machine-readable header, so a consumer greps the index and reads exactly the one
section it needs. `INTENT.md` is private to its skill. It is deliberately not a
lifecycle-protocol artifact kind.

Those skills document an **inline escape hatch** and the conditions under which it
is correct. Tight turn-by-turn iteration, cost on a lookup too small to justify
the dispatch, or an invoking context that is itself a subagent. Running inline
relaxes no discipline.

## Works in any repo

- **Self-contained.** The research discipline file (source tiers, recency gates,
  falsification recipes, failure patterns) and the per-ecosystem discovery
  reference ship inside the plugin and are referenced via `${CLAUDE_PLUGIN_ROOT}`.
  Explore composes `/toolchain:check`'s covered-ecosystem detection and root
  adjacency when that plugin is installed (documented fallback table when it is
  not; explore-owned inventories for build configs, runtime probes, and
  ecosystems the seam does not cover stay explore-owned). It does not bake a
  second covered-ecosystem inventory.
- **Reads your conventions, assumes none.** Project rules, preferred-source
  rosters, per-ecosystem source mappings, and any stated direction come from your
  own project's `CLAUDE.md` and rules; where none exist, the skills self-discover
  (llms.txt / sitemap probing, canonical-home identification).
- **Graceful degrade.** Adjacent capabilities: a workflow engine, subagents,
  synthesis MCP servers, documentation agents. Used when present and substituted when absent;
  no phase blocks on a missing tool, and substitutions are documented as gaps rather than silently
  lowering the bar.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install discovery@melodic-software
```

## Configuration

Artifact placement follows the plugin's lifecycle artifact protocol
(`reference/artifact-protocol.md`). `EXPLORE.md` / `RESEARCH.md` / `INTENT.md` are working
documents: they land in `<memory_dir>/<slug>/` (default `.work/<slug>/`), one slug per topic, never
committed, the memory root self-ignores. `<memory_dir>` is `.work/` unless your project
instructions declare another root.
`/discovery:setup check` reports read-only whether the session can run the dispatch design and
prints the gate allow rules to paste into `~/.claude/settings.json`; it writes nothing.

**`explore_output`.** A repository sets it for everyone in `docs/conventions/discovery.yaml`
(schema: `schemas/discovery.schema.json`), which wins over this option. A value outside `auto`,
`change-prep` and `explain` is reported with its file and key, and the run uses `auto`. Layers and
keys:
[`reference/config.md`](reference/config.md).

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `explore_output` | string | `"auto"` | `CLAUDE_PLUGIN_OPTION_EXPLORE_OUTPUT` | Reply shape of /discovery:explore. auto (default): explain when a person asks how something works, else change-prep, including calls from other skills. change-prep: the handoff summary. explain: a walkthrough citing path:line. EXPLORE.md is unchanged. docs/conventions/discovery.yaml overrides this. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure discovery@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install discovery@<marketplace> -s <scope> --config explore_output=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "discovery@<marketplace>": {
         "options": {
           "explore_output": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
