---
topic: context-command-output-contract
section: structured-output
abstract: A structured contextUsage object exists in the binary with snake_case fields and a stable category "kind" enum, but no CLI path exposes it — claude -p returns the markdown as a plain string in .result.
claims:
  - claim: "claude -p \"/context\" --output-format json returns the markdown as a plain STRING in the .result field; the envelope contains no contextUsage, context_usage, or structured_output field."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "local probe: claude -p \"/context\" --output-format json, v2.1.232, run 2026-08-17 — top-level keys enumerated programmatically"
        tier: 0
        pool: "empirical-cli-probe"
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (RIE returns the rendered string via metaMessages, 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
  - claim: "A structured builder exists in the shipped binary producing snake_case fields (model, total_tokens, raw_max_tokens, percentage, over_limit, categories[], mcp_tools[], memory_files[], agents[], skills[]) with a category kind enum of free|buffer|deferred|used."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (functions kVp, CVp, QLa and the XSv call site, byte-extracted 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
  - claim: "That structured object is reachable only over the control-protocol / thin-client path (get_context_usage), not from the CLI, and it is absent from the package's shipped SDK type definitions."
    confidence: MEDIUM
    tiers: [0, 1]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (command descriptor thinClientDispatch:\"control-request\"; sendControlRequest subtype get_context_usage, 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/sdk-tools.d.ts (grepped 2026-08-17 — no contextUsage/context_usage/raw_max_tokens)"
        tier: 0
        pool: "anthropic-shipped-sdk-types"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (v2.1.110 entry, fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-github-changelog"
produced_by: phase-2-falsification + phase-2-empirical
---

# Is there anything better than parsing markdown?

## The direct answer: not from the CLI

The probe settles it. `claude -p "/context" --output-format json` at v2.1.232 exits 0 and returns
an envelope whose top-level keys are:

```
is_error, duration_api_ms, num_turns, stop_reason, session_id, total_cost_usd,
usage, modelUsage, permission_denials, fast_mode_state, fast_mode_disabled_reason,
subtype, result, type, duration_ms, uuid
```

`result` is a **string** containing the same markdown. There is no `contextUsage`, no
`context_usage`, and no `structured_output`. `--output-format json` structures the *run envelope*,
never the slash command's payload.

Two adjacent flags do not help either:

- **`--json-schema <schema>`** constrains **model-generated** structured output. `/context` is a
  local command whose text is produced by the CLI itself without model involvement, so no schema
  applies to it.
- **`--output-format stream-json`** streams the same content as events; the payload is unchanged.

So for a CLI-driven measurement engine, **parsing the markdown is the only option**, and the
markdown is a first-class deterministic artifact rather than a pretty-printed afterthought — which
is the mitigating good news.

## The structured form that exists but is out of reach

The binary contains a builder that produces exactly the object a measurement engine would want:

```js
{
  model, total_tokens, raw_max_tokens, percentage,
  over_limit?: { tokens_over, kind },          // kind: "hard_limit" | "compaction_window"
  categories:   [{ name, tokens, kind }],       // kind: "free" | "buffer" | "deferred" | "used"
  mcp_tools:    [{ name, server_name, tokens }],
  memory_files: [{ path, type, tokens }],
  agents:       [{ agent_type, source, tokens }],
  skills?:      [{ name, source, plugin_name?, tokens }]
}
```

Its call site returns `{ type: "text", value: <the markdown>, contextUsage: <the object above> }` —
the markdown and the structured form side by side, from one data collection.

This object is strictly better than the markdown in four ways worth noting even though it is
unreachable: **exact integer token counts** (no `k` compaction, no `~` rounding, no `< 20`
sentinel), a **`kind` enum** that survives display-name renames, **`source` as the raw internal
enum** rather than a display label, and `plugin_name` as its own field instead of a parenthesised
suffix.

### Why the CLI cannot reach it

The command descriptor carries `thinClientDispatch: "control-request"`, and the command's own
implementation branches: when a remote connection is present it issues a control request with
subtype **`get_context_usage`** and renders the response; otherwise it collects locally and renders
to a string. **Both branches render.** The local branch never surfaces the structured object —
it hands the renderer's string to the conversation and returns `null`.

The structured path exists for **Remote Control clients** (mobile/web), which changelog v2.1.110
dates: "`/context`, `/exit`, and `/reload-plugins` now work from Remote Control (mobile/web)
clients."

### Confidence and its limit

This claim is marked **MEDIUM**, not HIGH, deliberately. What is Tier-0 certain: the builder
exists, its field names and enums are as quoted, the descriptor declares control-request dispatch,
and the CLI JSON envelope does not carry it. What is **not** established: whether some SDK,
control-channel, or thin-client entry point available to a plugin author can invoke it. The
package's shipped `sdk-tools.d.ts` was grepped and contains no `contextUsage`, `context_usage`, or
`raw_max_tokens` — so it is not in the shipped tool type surface. But the Agent SDK is a separate
package that was **not** examined, and the control protocol is not publicly documented.

**Checked:** the shipped v2.1.232 binary, the package's `sdk-tools.d.ts`, `claude --help` in full,
an executed `--output-format json` probe, the docs sitemap enumeration, and two web searches for a
structured `/context` output. **Left unchecked:** the `@anthropic-ai/claude-agent-sdk` package
itself, `/en/agent-sdk/*` reference pages beyond `tool-search`, and the control-protocol wire
format. **This is the one open question worth chasing before committing to a markdown parser** —
if the Agent SDK exposes `get_context_usage`, the measurement engine could take the structured
object and skip the markdown contract entirely.

## Recommendation for the skill

Parse the markdown, but treat it as a versioned de-facto contract:

1. Invoke as `claude -p "/context all" --output-format json` and take `.result`. Passing `all`
   makes expansion explicit rather than a side effect of not being in fullscreen; `--output-format
   json` gives a clean envelope and an exit status instead of mixed stdout.
2. **Redirect stdin** (`< /dev/null`). The probe's first run prepended a `Warning: no stdin data
   received in 3s` line to stdout, which broke `JSON.parse` outright. This is a real and easily
   missed failure mode for a non-interactive measurement engine.
3. Record `claude --version` with every measurement and invalidate baselines on change.
4. Anchor parsing on `###` section headers and on column names; tolerate absent sections; and
   treat an unknown category name as an error rather than silently dropping it.
