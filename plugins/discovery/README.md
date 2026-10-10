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
| `/discovery:read-docs` | External, one page | Reads one upstream docs page through the shared docs lookup and cache (`scripts/fetch-docs.sh`, `scripts/docs-cache.sh`): the whole page when small, otherwise the section map, stored summaries and notes, and the sections the model picks. Marks what the page does not state, keeps inference in a labeled part, and stores summaries and a quote-checked note for the next reader. Verification reads raw bytes only. The procedure is `reference/docs-lookup-procedure.md`, a generated copy other plugins can carry. |
| `/discovery:check` | Setup | Reports whether `node` resolves, whether `hooks/hooks.json` registers the WebFetch truncation hook, and whether the hook flags a sample truncated result. Read-only; installs nothing. |
| `/discovery:blindspot` | Local, user-facing | Surfaces the USER's unknown-unknowns before they work in unfamiliar territory (a codebase area or a domain vocabulary), emitting blindspot cards and coaching one improved prompt. Deliverable is the user's understanding, not `EXPLORE.md`. |

`discovery:report` is the return-contract skill: not user-invocable, and the canonical copy that `implementation` and `plugin-quality` mirror byte-identically. No discovery agent preloads it: each agent's own `Return exactly this` section is its whole return shape.

| Agent | Dispatched by | What it does |
|---|---|---|
| `discovery:explorer` | `/discovery:explore` | Runs the six dimensions in a fresh context, loads path-scoped project rules explicitly, writes the artifact set, returns a bounded summary and a file pointer. |
| `discovery:researcher` | `/discovery:research`, `/discovery:research-deep` | Runs the full research discipline in a fresh context, writes the artifact set and coverage ledger, returns a file pointer plus a verification request. |
| `discovery:research-verifier` | `/discovery:research`, `/discovery:research-deep` | Read-only. Grades a research artifact's verifier-owned outcome-gate rows in a fresh context and returns the `verification:` line the parent writes into `RESEARCH.md`. |
| `discovery:sweep-worker` | the `discovery:research-sweep` workflow | Runs one workflow stage with web search and fetch only, so no stage that reads untrusted pages holds a shell or file access. Inherits the model and pins no effort; the workflow passes both from the role map. |
| `discovery:docs-fetcher` | the `discovery:research-sweep` workflow | Runs `scripts/docs-raw.sh` once on one URL and returns its output: a fresh, raw read of the page or its section map. Holds `Bash` only, and `hooks/hooks.json` registers `lib/docs-fetcher-gate.mjs` on `Bash` to deny it any other command or a non-public host; for the one allowed command the gate returns no decision, so the session's permission rules still apply. It gets a URL and section ids, never the question or a claim. The command passes once per agent run, so a page cannot steer a second fetch. The gate checks only the host written in the command, so `docs-raw.sh` runs `fetch-docs.sh --public-only`: every address the host resolves to must be global, or the page is unread `private-address`, and curl then connects only to the checked address (`--connect-to`, no proxy, no `~/.curlrc`), so neither an https redirect to another host nor a second DNS answer reaches a private network. This is OWASP's case 2 check for open destinations rather than a host allowlist, which an open research sweep cannot have ([SSRF prevention cheat sheet](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html)). The gate fails open when `node` is missing or the hook times out: Claude Code treats that hook error as non-blocking, and the session's permission rules alone hold this agent's `Bash`; a stdin error or a crash inside the gate denies. The gate is always-on: one process (`node`) per `Bash` call, ratcheted in `.performance/ratchets.json` as `discovery-pretooluse-bash-docs-fetcher-gate-spawns`. |
| `discovery:intent-tracer` | `/discovery:trace-intent` | Investigates the resolvable evidence categories in a fresh context, grades each claim on the intent-evidence tier, writes the artifact set, and returns a file pointer plus a verification request. |

| Workflow | Launched by | What it does |
|---|---|---|
| `/discovery:research-sweep` (`workflows/research-sweep.js`) | `/discovery:research-deep` Tier 1 | Sweeps sources for one question by angle, deep-reads the best of them, has three independent skeptics try to refute each load-bearing claim (a claim survives on a majority; a skeptic that could not check counts as unverified, not refuted), runs a completeness critic, and returns findings with citations, source tier, date and consensus counts, plus dissent and unverified claims. `args`: `question` (required; without it nothing runs), `angles`, `sources`, `roles` (the map `/multi-agent:route all research` prints; without it, fan-out stages run on `opus`), `maxConcurrent` (default 4) and `artifactPath`. A fetch stage first reads each selected https page raw through `discovery:docs-fetcher`; readers and skeptics get those slices inline and may ask for sections they lack. Every other stage runs as `discovery:sweep-worker`, reads only public http(s) URLs, and receives page-derived text as fenced JSON. It writes no files: `research-deep` writes `RESEARCH.md` from the result. |

The `docs-fetcher` and `sweep-worker` definitions set `omitClaudeMd: true`:
each reads untrusted pages and follows only the prompt the workflow gives it,
so it starts without the user and project instruction files. The pointer sits
here, not in the agent bodies, so neither agent spends a fetch on it.

- **Pointer**: when you need what the field drops and what still loads, fetch
  [sub-agents: supported frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields)
  and [sub-agents: what loads at startup](https://code.claude.com/docs/en/sub-agents#what-loads-at-startup)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: the sub-agents `omitClaudeMd` row or the startup
  section changes what the field drops or keeps.

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
- **As of**: 2026-10-10
- **Recheck trigger**: that section documents the note text or the `offset` input.

The hook is partial by design. It has no length rule, so a page WebFetch summarized with no marker
or placeholder gets no note; the captured CHANGELOG fetch is one. The routing rule in the
[upstream-drift convention](../../docs/conventions/upstream-drift/README.md#the-rungs) covers that
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

## Requirements

- **Node.js** for the WebFetch truncation hook. Without `node` the hook cannot start, and a
  truncated WebFetch result gets no note. A `SessionStart` notice names `/discovery:check`, which
  reports whether `node` resolves and the hook is registered.
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
`/discovery:setup check` reports read-only whether the session can run the dispatch design and
prints the gate allow rules to paste into `~/.claude/settings.json`; it writes nothing.

## License

MIT (SPDX-License-Identifier: MIT).
