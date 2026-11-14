# discovery

A Claude Code plugin for **structured discovery before changes**. Understand what
IS (the local codebase), what SHOULD BE (current external sources), and what WAS
and why (the reasoning behind a past decision) before any code is written. Those
three skills sit on the evidence-source axis and **dispatch a purpose-built
subagent by default**, so the reading stays out of the main conversation;
`blindspot` serves the USER's understanding rather than the agent's.

| Skill | Axis | What it does |
|---|---|---|
| `/discovery:explore` | Local | Six-dimension codebase exploration, code reading, git history, project structure, test discovery, build config, environment, persisting an `EXPLORE.md` index plus sidecars. Dispatches `discovery:explorer` by default. |
| `/discovery:research` | External | Corpus enumeration, then three chained research phases (broad → targeted + falsification → preferred sources) with per-claim source tiers, independent-corroborator ratios, a recency gate, a coverage ledger, and a binary outcome gate before presenting. Dispatches `discovery:researcher` by default. Its deep tier, chosen in the main conversation for a multi-topic ask, a topic that needs adversarial verification, or a leading `deep` token, fans one `discovery:researcher` out per separable topic or launches the `discovery:research-sweep` workflow when the `Workflow` tool is in the session. |
| `/discovery:trace-intent` | Historical | Reconstructs why a thing was built the way it was, from evidence outside the code: review discussion, tickets, long-form documents. Grades every claim on an intent-evidence tier (Direct / Supported / Inferred / Speculative / Unknown), cites each one with a source-reliability note, and reports what it could not find in a coverage map. Dispatches `discovery:intent-tracer` by default. |
| `/discovery:read-docs` | External, one page | Reads one upstream docs page through the shared docs lookup and cache (`scripts/fetch-docs.sh`, `scripts/docs-cache.sh`): the whole page when small, otherwise the section map, stored summaries and notes, and the sections the model picks. Marks what the page does not state, keeps inference in a labeled part, and stores summaries and a quote-checked note for the next reader. Verification reads raw bytes only. The procedure is `reference/docs-lookup-procedure.md`, a generated copy other plugins can carry. |
| `/discovery:blindspot` | Local, user-facing | Surfaces the USER's unknown-unknowns before they work in unfamiliar territory (a codebase area or a domain vocabulary), emitting blindspot cards and coaching one improved prompt. Deliverable is the user's understanding, not `EXPLORE.md`. |

`discovery:report` is the return-contract skill: not user-invocable, and the canonical copy that `implementation` and `plugin-quality` mirror byte-identically. No discovery agent preloads it: each agent's own `Return exactly this` section is its whole return shape.

| Agent | Dispatched by | What it does |
|---|---|---|
| `discovery:explorer` | `/discovery:explore` | Runs the six dimensions in a fresh context, loads path-scoped project rules explicitly, writes the artifact set, returns a bounded summary and a file pointer. |
| `discovery:researcher` | `/discovery:research` | Runs the full research discipline in a fresh context, writes the artifact set and coverage ledger, returns a file pointer plus a verification request. |
| `discovery:research-verifier` | `/discovery:research` | Read-only. Grades a research artifact's verifier-owned outcome-gate rows in a fresh context and returns the `verification:` line the parent writes into `RESEARCH.md`. |
| `discovery:sweep-worker` | the `discovery:research-sweep` workflow | Runs one workflow stage with web search and fetch only, so no stage that reads untrusted pages holds a shell or file access. Inherits the model and pins no effort; the workflow passes both from the role map. |
| `discovery:docs-fetcher` | the `discovery:research-sweep` workflow | Runs `scripts/docs-raw.sh` once on one URL and returns its output: a fresh, raw read of the page or its section map. Holds `Bash` only, and `hooks/hooks.json` registers `lib/docs-fetcher-gate.mjs` on `Bash` to deny it any other command or a non-public host; for the one allowed command the gate returns no decision, so the session's permission rules still apply. It gets a URL and section ids, never the question or a claim. The command passes once per agent run, so a page cannot steer a second fetch. The gate checks only the host written in the command, so `docs-raw.sh` runs `fetch-docs.sh --public-only`: every address the host resolves to must be global, or the page is unread `private-address`, and curl then connects only to the checked address (`--connect-to`, no proxy, no `~/.curlrc`), so neither an https redirect to another host nor a second DNS answer reaches a private network. This is OWASP's case 2 check for open destinations rather than a host allowlist, which an open research sweep cannot have ([SSRF prevention cheat sheet](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html)). A stdin error or a crash inside the gate denies. The row sets `"onFailure": "block"`, so when `node` is missing or the hook times out, Claude Code 2.1.295 or later denies the call, in every agent and the main thread; an older client ignores the key and lets the call go ahead, leaving this agent's `Bash` to the session's permission rules alone ([hook budget](../../docs/contracts/hook-budget/README.md#which-rows-set-onfailure-block)). The gate is always-on: one process (`node`) per `Bash` call, ratcheted in `.performance/ratchets.json` as `discovery-pretooluse-bash-docs-fetcher-gate-spawns`. |
| `discovery:intent-tracer` | `/discovery:trace-intent` | Investigates the resolvable evidence categories in a fresh context, grades each claim on the intent-evidence tier, writes the artifact set, and returns a file pointer plus a verification request. |

| Workflow | Launched by | What it does |
|---|---|---|
| `/discovery:research-sweep` (`workflows/research-sweep.js`) | `/discovery:research` deep tier | Sweeps sources for one question by angle, deep-reads the best of them, has three independent skeptics try to refute each claim the answer depends on (a claim survives on a majority; a skeptic that could not check counts as unverified, not refuted), runs a completeness critic, and returns findings with citations, source tier, date and consensus counts, plus dissent and unverified claims. `args`: `question` (required; without it nothing runs), `angles`, `sources`, `roles` (the map `/multi-agent:route all research` prints; without it, fan-out stages run on `opus`), `maxConcurrent` (default 4) and `artifactPath`. A fetch stage first reads each selected https page raw through `discovery:docs-fetcher`; readers and skeptics get those slices inline and may ask for sections they lack. Every other stage runs as `discovery:sweep-worker`, reads only public http(s) URLs, and receives page-derived text as fenced JSON. It writes no files: `/discovery:research` writes `RESEARCH.md` from the result. |

The `docs-fetcher` and `sweep-worker` definitions set `omitClaudeMd: true`:
each reads untrusted pages and follows only the prompt the workflow gives it,
so it starts without the user and project instruction files. The pointer sits
here, not in the agent bodies, so neither agent spends a fetch on it.

- **Pointer**: when you need what the field drops and what still loads, fetch
  [sub-agents: supported frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields)
  and [sub-agents: what loads at startup](https://code.claude.com/docs/en/sub-agents#what-loads-at-startup)
  live.

The three artifact-persisting skills (`/discovery:explore`, `/discovery:research`,
`/discovery:trace-intent`) persist handoff artifacts (`EXPLORE.md` / `RESEARCH.md`
/ `INTENT.md`) so a fresh session can resume planning from the artifact alone.
Each is **always an index**, with content in sibling sidecars carrying a
machine-readable header, so a consumer greps the index and reads exactly the one
section it needs. `INTENT.md` is private to its skill. It is deliberately not a
lifecycle-protocol artifact kind.

Those skills document an **inline escape hatch** and the conditions under which it
is correct: tight turn-by-turn iteration, a lookup too small to justify the
dispatch cost, or an invoking context that is itself a subagent. Running inline
relaxes no discipline.

## The WebFetch truncation hook

A `PostToolUse` hook on `WebFetch` (`hooks/webfetch-truncation.mjs`) adds one line of context when
the result's last line is a truncation marker or placeholder, such as `[Content truncated for
length...]` or `[... content continues ...]`: the result covers only part of the page, and
`/discovery:read-docs` reads the rest. It never blocks a call or changes the result, and it does not
echo the fetched line back.

On current Claude Code, WebFetch ends a result for a page over its read cap with its own read-on
note and takes an optional `offset` input. The hook flags that note too, and for it the context
line says to call WebFetch again with the same URL and the offset the note names, with
`/discovery:read-docs` as the other route. Probed on Claude Code 2.1.296, 2026-10-10; evidence in
the pull request that carries this change.

- **Pointer**: when you need what WebFetch documents about pages over its read cap, fetch
  [tools reference: WebFetch tool behavior](https://code.claude.com/docs/en/tools-reference#webfetch-tool-behavior)
  live.

The hook is partial by design. It has no length rule, so a page WebFetch summarized with no marker
or placeholder gets no note; the captured CHANGELOG fetch is one. The routing rule in the
[upstream-drift convention](../../docs/contracts/upstream-drift/README.md#the-rungs) covers that
case: a verification, absence or completeness read goes through `/discovery:read-docs`, whatever
WebFetch returned.

It is a settings hook, not a mod: it adds context after one tool call, which a settings hook does
natively, and it then also runs where mods are off
([ADR 0052](../../docs/adr/0052-adopt-claude-code-mods.md)).

Tested against three `PostToolUse` payloads captured from a headless `claude -p` session on Claude
Code 2.1.289 (`hooks/fixtures/`): `hooks` (fires), `env-vars` and `CHANGELOG.md` (summaries, stay
quiet). Interactive sessions and WebFetch calls made inside subagents were not captured; the hook
reads only `tool_name`, `tool_input.url` and `tool_response.result`, and stays quiet on any other
shape.

## Works in any repo

- **Self-contained.** The research discipline file (source tiers, recency gates,
  falsification recipes, failure patterns) and the per-ecosystem discovery
  reference ship inside the plugin and are referenced via `${CLAUDE_PLUGIN_ROOT}`.
  Explore composes `/toolchain:check`'s covered-ecosystem detection and root
  adjacency when that plugin is installed (documented fallback table when it is
  not; explore-owned inventories for build configs, runtime probes, and
  ecosystems `/toolchain:check` does not cover stay explore-owned). It does not bake a
  second covered-ecosystem inventory.
- **Reads your conventions, assumes none.** Project rules, preferred-source
  rosters, per-ecosystem source mappings, and any stated direction come from your
  own project's `CLAUDE.md` and rules; where none exist, the skills self-discover
  (llms.txt / sitemap probing, canonical-home identification).
- **Graceful degrade.** Adjacent capabilities: a workflow engine, subagents,
  synthesis MCP servers, documentation agents. Used when present and substituted when absent;
  no phase blocks on a missing tool, and substitutions are documented as gaps rather than silently
  lowering the bar.

## Requirements

- **Node.js** for the WebFetch truncation hook and the `docs-fetcher` gate. Without `node` the
  truncation hook cannot start, and a truncated WebFetch result gets no note. The gate's row sets
  `"onFailure": "block"`, so on Claude Code 2.1.295 or later every `Bash` call is denied until
  `node` resolves. `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"` reports whether
  `node` resolves; `bash "<plugin root>/scripts/check-hook-registration.sh"` then reports whether
  `hooks/hooks.json` registers the truncation hook and whether the hook flags a sample truncated
  result. Both are read-only.
- **curl and jq** for `/discovery:read-docs`; **Python 3**, optional, converts a page served only
  as HTML. Each is declared in `prerequisites.json` with what degrades without it.

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
`/discovery:setup check` reports read-only whether the session can run the dispatch design, prints
the gate allow rules to paste into `~/.claude/settings.json`, and validates
`docs/conventions/discovery.yaml`. `/discovery:setup apply` writes that file, plus, on an explicit yes, a convention-home region in
the instruction file and an ignore line in `.gitignore`: it
validates against the schema first and shows the diff and asks before changing an existing file.

**`explore_output`.** A repository sets it for everyone in `docs/conventions/discovery.yaml`
(schema: `schemas/discovery.schema.json`), which wins over this option. A value outside `auto`,
`change-prep` and `explain` is reported with its file and key, and the run uses `auto`. Layers and
keys:
[`reference/config.md`](reference/config.md).

**`research_corroborators`, `research_recency_*_days`.** `/discovery:research`'s per-claim
corroborator floor (default 2) and its recency windows (14, 30 and 90 days). They resolve through
the same layers, and each run reports the values and the layer that supplied them.

**Agent models.** `explorer` runs on `sonnet`; `researcher`, `intent-tracer` and
`research-verifier` run on `opus`. With the `multi-agent` plugin enabled, a model set in one of its
config layers for the agent's role replaces that pin on the spawn: `retrieval` for `explorer`,
`worker` for `researcher` and `intent-tracer`, `verifier` for `research-verifier`. Set it on the
`research` workload to move these agents and the `research-sweep` stages without moving other
plugins' agents in that role, for example
`roles.worker.workloads.research.model: sonnet` in `.claude/multi-agent.local.yaml`. Layers and
keys: the multi-agent plugin's `reference/config.md`. A layer value of `inherit` keeps the pin,
because a spawn's `model` takes an alias only
([sub-agents: choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model)). With no such layer, or without `multi-agent`, the
pins apply. The rule: `reference/parent-contract.md`, "The worker's model is the parent's call".

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `explore_output` | string | `"auto"` | Reply shape of /discovery:explore. auto (default): explain when a person asks how something works, else change-prep, including calls from other skills. change-prep: the handoff summary. explain: a walkthrough citing path:line. EXPLORE.md is unchanged. docs/conventions/discovery.yaml overrides this. |
| `research_corroborators` | number<br>*min 1* | `2` | Independent current corroborators /discovery:research needs per accepted claim beside its primary. Default 2. The broad-topic minimum and the single-source exception are unchanged. docs/conventions/discovery.yaml overrides this. |
| `research_recency_active_days` | number<br>*min 1* | `14` | Recency window /discovery:research applies to a very active project (weekly releases, breaking changes, security-sensitive). Default 14. docs/conventions/discovery.yaml overrides this. |
| `research_recency_standard_days` | number<br>*min 1* | `30` | Recency window /discovery:research applies to a standard library, tool, CLI or API. Default 30. docs/conventions/discovery.yaml overrides this. |
| `research_recency_guide_days` | number<br>*min 1* | `90` | Recency window /discovery:research applies to a tool- or vendor-specific architecture guide. Default 90. docs/conventions/discovery.yaml overrides this. |
| `medium` | string | `"auto"` | Where the /discovery:blindspot view goes. auto (default): a local file. terminal: no page; file: a local file; artifact: a private Artifact; hosted = artifact. A terminal or file value in any rendered-views setting wins over this option. |

### How to set these

Set the options above for `discovery@<marketplace>`, replacing `<marketplace>` with the
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

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
