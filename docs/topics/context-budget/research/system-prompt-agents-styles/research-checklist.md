# Coverage ledger — system prompt, custom agents, output styles

**Corpus verdict: BOUNDED.** Three named subjects, each with a finite first-party surface. Enumerated
before the first query from surfaces exhaustive by construction:

- `https://code.claude.com/docs/sitemap.xml` (fetched 2026-08-17) → 187 `/docs/en/` pages; the rows
  below are the subset whose titles bear on system prompt / agents / output styles / startup payload.
- `claude --help` on the locally installed binary, v2.1.232 (Tier 0, captured 2026-08-17) → the
  complete flag surface, which is what makes the flag rows (11-15) enumerable rather than guessed.
- The npm-installed `@anthropic-ai/claude-code` bundle on disk (Tier 0) → the shipped implementation.

**Narrowing recorded:** the 187-page sitemap is not all covered. Pages with no bearing on the three
subjects (gateways, Bedrock/Vertex, Slack, desktop, self-hosted environments, billing) are out of
scope by construction, not skipped silently. The `whats-new/*` weekly pages are covered as a single
recency row (19) rather than 19 rows.

| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | `docs/en/cli-reference` | every flag bearing on system-prompt content read; `--system-prompt`, `--append-system-prompt`, `--safe-mode`, `--bare`, `--exclude-dynamic-system-prompt-sections` each confirmed present-or-absent | [x] |
| 2 | `docs/en/output-styles` | page read end to end; what it replaces vs. adds, and enable/disable mechanism, both extracted verbatim | [x] |
| 3 | `docs/en/sub-agents` | page read end to end; the section describing what is loaded up front vs. on invocation extracted | [x] |
| 4 | `docs/en/agents` | page read; relationship to sub-agents and any disable/enable key extracted | [x] |
| 5 | `docs/en/settings` | full settings-key table scanned for `outputStyle`, agent-disable, system-prompt keys | [x] |
| 6 | `docs/en/env-vars` | full env-var table scanned for `CLAUDE_CODE_SIMPLE`, `CLAUDE_CODE_SAFE_MODE`, and any system-prompt var | [x] |
| 7 | `docs/en/context-window` | the `/context` breakdown rows enumerated; which of the three subjects appears as its own row | [x] |
| 8 | `docs/en/how-claude-code-works` | any statement about system-prompt composition at startup read | [x] |
| 9 | `docs/en/agent-sdk/modifying-system-prompts` | the three system-prompt modes (preset/append/custom) read end to end; whether the CLI shares them | [x] |
| 10 | `docs/en/plugins-reference` | `agents/` and `output-styles/` plugin component sections read; load semantics extracted | [x] |
| 11 | `claude --help` (Tier 0, v2.1.232) | complete option list captured; every candidate flag's own help text quoted | [x] |
| 12 | `--bare` / `CLAUDE_CODE_SIMPLE` | flag's own help text quoted; documented-vs-undocumented status settled against docs pages 1 and 6 | [x] |
| 13 | `--safe-mode` / `CLAUDE_CODE_SAFE_MODE` | flag's own help text quoted; the enumerated list of what it disables captured | [x] |
| 14 | `--exclude-dynamic-system-prompt-sections` | flag's own help text quoted; whether it REDUCES or RELOCATES settled | [x] |
| 15 | `--system-prompt` / `--append-system-prompt` | each flag's help text quoted; replace-vs-add semantics settled from a first-party source | [x] |
| 16 | Shipped bundle strings (Tier 0) | the installed `@anthropic-ai/claude-code` searched for the Environment-block template, git-status injection, and the three env vars | [x] |
| 17 | `claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models` | fetched; the 80%-removal claim located verbatim or its absence recorded with the surfaces checked | [x] |
| 18 | `docs/en/plugin-relevance` | whether plugin-provided components load unconditionally or are gated; applied to agents and output styles | [x] |
| 19 | Recency: `docs/en/changelog` + `whats-new/*` latest | latest release confirmed this turn; every accepted lever cross-checked against it | [x] |
| 20 | `docs/en/interactive-mode` + `docs/en/commands` | `/output-style`, `/agents`, `/context` slash-command surface confirmed | [x] |
| 21 | `docs/en/plugins` | plugin enable/disable granularity read; whether a component can be disabled apart from its plugin | [x] |
| 22 | `docs/en/memory` | checked only for whether CLAUDE.md discovery is part of the system prompt block or separate | [x] |
