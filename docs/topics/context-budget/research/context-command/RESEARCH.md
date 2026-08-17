# RESEARCH — the /context output contract in Claude Code v2.1.232

## Task restatement

Establish, for the author of a skill whose measurement engine will parse `/context` output: what
each row of that output means, what "System tools" actually contains, and whether any
machine-readable form exists. Seven specific questions were asked — official documentation and
format stability, the composition of "System tools" and any per-tool attribution switch, the
meaning of "System tools (deferred)" and its relation to `ToolSearch` and MCP deferral, whether
configured MCP servers add rows, whether `CLAUDE.md` memory files still get their own row at
2.1.232, the exact meaning of the four `Source` values including "claude.ai sync" and its off
switch, and any JSON/structured alternative to parsing markdown.

The parent supplied an empirical probe (`claude -p "/context"`, v2.1.232, exit 0) that showed a
category table, per-agent and per-skill tables with a `Source` column, **no** per-tool breakdown,
and **no** MCP row.

## How this run was able to answer definitively

Claude Code **v2.1.232 is installed on this machine** at
`node_modules/@anthropic-ai/claude-code`, shipping as a Bun-compiled native binary with its
JavaScript embedded as extractable text. The renderer, the token-accounting functions, the
category list, the `Source` label maps, and the structured-output builder were all read directly
from that binary (Tier 0), then confirmed by executing the same binary under modified conditions
(Tier 0), then cross-checked against Anthropic's docs and changelog (Tier 1).

A version trap was caught and avoided: a second, older install at
`/opt/node22/lib/node_modules/@anthropic-ai/claude-code` is **v2.1.42**, and its category list
differs from 2.1.232's. Nothing in this artifact is sourced from it.

## Abstracts

- **output-contract** — The `/context` markdown is emitted by one deterministic generator with a
  fixed six-section order and two distinct token formatters; skill rows alone carry `~` or `< 20`.
- **category-semantics** — "System tools" is one aggregate block of non-deferred built-in tool
  schemas plus any deferred tools already invoked, minus skill frontmatter; no per-tool attribution
  exists because the field that would carry it is always empty.
- **conditional-rows** — MCP servers add both a category row and a per-tool/per-server MCP Tools
  section; `CLAUDE.md` files still produce a Memory files row and a Memory Files section at
  2.1.232 — both were merely absent from the probe, not removed.
- **source-values** — Source values come from one enum-to-label map; "claude.ai sync" marks skills
  synced from the user's claude.ai account, and no global off switch exists at 2.1.232 — only
  per-skill `skillOverrides`.
- **documentation-and-stability** — Only the command's existence and its `all` argument are
  documented; the output schema is documented nowhere, carries no stability guarantee, and has
  changed shape roughly every 30 releases.
- **structured-output** — A structured `contextUsage` object exists in the binary with snake_case
  fields and a stable category `kind` enum, but no CLI path exposes it — `claude -p` returns the
  markdown as a plain string in `.result`.

## Sections

| Section | File | Anchor | Answers |
|---|---|---|---|
| Output contract | [`RESEARCH-output-contract.md`](RESEARCH-output-contract.md) | `#the-context-output-contract-in-v212232` | Q1 (schema half) |
| Category semantics | [`RESEARCH-category-semantics.md`](RESEARCH-category-semantics.md) | `#what-each-category-row-actually-contains` | Q2, Q3 |
| Conditional rows | [`RESEARCH-conditional-rows.md`](RESEARCH-conditional-rows.md) | `#the-conditional-rows-the-probe-could-not-see` | Q4, Q5 |
| Source values | [`RESEARCH-source-values.md`](RESEARCH-source-values.md) | `#what-the-source-column-means` | Q6 |
| Documentation & stability | [`RESEARCH-documentation-and-stability.md`](RESEARCH-documentation-and-stability.md) | `#is-the-format-documented-is-it-stable` | Q1 |
| Structured output | [`RESEARCH-structured-output.md`](RESEARCH-structured-output.md) | `#is-there-anything-better-than-parsing-markdown` | Q7 |

Coverage ledger: [`research-checklist.md`](research-checklist.md) — 12 rows, all marked;
`check-coverage-complete.sh` exits 0.

## Direct answers to the seven questions

1. **Documented?** Only that the command exists and takes `[all]`. No output schema anywhere in
   the docs sitemap (enumerated in full, no `/context` page in any locale). **Per-skill/per-agent
   tables grouped by source arrived in v2.0.74; `Plugin (name)` in v2.1.139.** No stability
   statement exists in either direction — the format is not presented as an interface at all, and
   it has changed materially at v2.0.74, v2.1.0, v2.1.129, v2.1.139 and v2.1.216. **Brittle.**
2. **"System tools"** = non-deferred built-in (non-MCP) tool definitions measured as **one batch**,
   plus deferred built-ins already invoked this session, **minus skill-frontmatter tokens** (which
   are counted separately under `Skills`). No per-tool breakdown exists and **no flag, argument or
   env var produces one** — the `systemToolDetails` array is initialised empty and never populated
   on any return path, and its emission site is disabled by a comma-expression guard. `/context`'s
   only argument is `all`, which expands *existing* detail sections and creates none.
3. **"System tools (deferred)"** = built-in tools withheld from context by **tool search** and not
   yet invoked. A tool moves from this row into `System tools` the moment it is first called. The
   row **disappears entirely** when tool search is off (`ENABLE_TOOL_SEARCH=false`, a non-first-party
   `ANTHROPIC_BASE_URL`, Azure-hosted Foundry, older Vertex models), with its tokens folded into
   `System tools`. `MCP tools (deferred)` is its MCP-origin sibling; both share one budget.
4. **MCP: yes, confirmed empirically.** With a server configured, a category row appears — as
   `MCP tools (deferred)` under default tool search, or `MCP tools` without it — plus a
   `### MCP Tools` section with **per-tool and per-server** columns `Tool | Server | Tokens`. It
   sits between the category table and Custom Agents.
5. **Memory files: still present at 2.1.232, confirmed empirically.** The earlier internal note was
   correct and nothing replaced it. Both a `Memory files` category row and a `### Memory Files`
   section (`Type | Path | Tokens`, absolute paths) appear — they are simply omitted when no
   `CLAUDE.md` is loaded, which is why the probe missed them.
6. **Source values** come from one map: `Built-in` = ships inside Claude Code; `User` =
   `~/.claude/skills/`; `Plugin (x)` = from installed plugin *x*; **`claude.ai sync` = synced from
   the user's claude.ai account** (Skills panel / Cowork plugins, delivered at session start with
   no local install). **No global off switch exists at 2.1.232** — `disableClaudeAiConnectors`
   covers MCP connectors only, `disableBundledSkills` covers bundled skills only. The only lever is
   **per-skill `skillOverrides`** (`off` / `user-invocable-only`), settable via `/skills` or
   settings, and undocumented on the settings page.
7. **No structured CLI output.** `--output-format json` puts the markdown in `.result` as a
   **string**; the envelope has no `contextUsage` or `structured_output`. A structured builder
   *does* exist in the binary — exact integers, a `free|buffer|deferred|used` kind enum, raw source
   enums, `plugin_name` as its own field — but it is dispatched over the control protocol
   (`get_context_usage`) for Remote Control clients and is absent from the shipped SDK types.

## Next-stage handoff

**Settled — safe to build on:**

- Section order is fixed and sections are omitted, never empty. Parse by `###` header and column
  name, never by index.
- Category rows are gated `tokens > 0`; `Free space` and `Autocompact buffer` are always appended
  last, in that order; `Compact buffer` is a possible alternative name for the latter.
- Category-table percentages are one-decimal (`0.0%` is a real, non-empty row); the header
  percentage is an integer. They are computed differently — do not cross-check one against the other.
- **Skill token cells need three shapes handled: `~<int>`, `< 20`, and nothing else.** Every other
  token cell uses the compact `18.1k` form. Neither gives exact integers.
- Agent rows render `Plugin` **without** a name; skill rows render `Plugin (name)`. Agents cannot
  be attributed to a plugin from this output.
- Invoke with `< /dev/null` — an unredirected stdin prepends a warning line that breaks JSON parsing.
- Pin `claude --version` with every measurement; treat a version change as invalidating baselines.

**Open decisions for the skill author:**

- **Chase the Agent SDK before committing to a markdown parser.** If `@anthropic-ai/claude-agent-sdk`
  or the control protocol exposes `get_context_usage`, the structured object removes the entire
  brittleness problem. This run did not examine that package (see Gaps).
- Decide whether the engine sums `System tools` + `System tools (deferred)` for cross-environment
  comparability. Recommended — the split is environment-dependent, not configuration-dependent.
- Decide whether skill-token precision (`~`, rounded to 10, `< 20` floor) is sufficient for the
  measurement being built. It bounds achievable resolution at roughly ±5 tokens per skill and
  cannot be improved from this surface.

## Gaps and unverified claims

- **Whether any SDK or control-channel entry point exposes the structured `contextUsage`** —
  marked MEDIUM confidence and explicitly **unverified**. Checked: the binary, the package's
  `sdk-tools.d.ts`, `claude --help`, the JSON envelope, the docs sitemap, two web searches. Left
  unchecked: the `@anthropic-ai/claude-agent-sdk` package and the control-protocol wire format.
- **`skillOverrides` as the synced-skill off switch is sourced on the binary alone** — Tier 0, but
  not independently corroborated and absent from the official settings page. The independent
  corroborator found (issue #39686) confirms only the *absence of a global switch*, was filed at
  v2.1.84, and does not mention `skillOverrides`.
- **Publisher independence is structurally limited.** Every authoritative source here is Anthropic
  (binary, docs, changelog). The three evidence *methods* are independent — code extraction,
  execution, vendor prose — but they are not independent publishers, and **no third party
  documents this format at all**, which the falsification search confirmed. Confidence ratings rest
  on Tier-0 execution agreeing with Tier-0 code inspection, not on publisher diversity. A verifier
  should grade criterion 4 with this constraint in view.
- **Not fetched in full:** `/en/env-vars`, `/en/headless`, `/en/cli-reference`, `/en/costs`,
  `/en/skills`. None is a likely home for a slash-command output schema, but `/en/env-vars` or
  `/en/skills` could document `skillOverrides`.
- **The comma-expression guard** disabling the System-tools and system-prompt-sections markdown
  blocks is read off minified code. That it produces no output is certain (confirmed by probe);
  whether it is an upstream bug or deliberate dead code is **unverified** and unknowable from here.

## Recency

Upstream latest release at fetch time: **2.1.233** (CHANGELOG.md fetched 2026-08-17), one patch
ahead of the 2.1.232 under study. Its single entry concerns GitLab merge-request URL support in
`--worktree` and `claude agents` — **no bearing on `/context`**. No `/context` change is recorded
between 2.1.218 and 2.1.233, so every claim here is current as of the latest release. Verdict:
**current**.
