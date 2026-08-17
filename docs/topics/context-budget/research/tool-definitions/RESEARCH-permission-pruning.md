---
topic: tool-definitions-prefix-pruning
section: permission-pruning
abstract: "The docs are explicit, not silent: a BARE tool name in disallowedTools or permissions.deny removes the definition from the request, while a SCOPED rule only blocks calls — confirmed verbatim and reproduced empirically."
claims:
  - claim: "A bare tool name in a deny rule removes the tool from Claude's context entirely; a scoped rule leaves the tool available and only blocks matching calls."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/permissions#manage-permissions"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/cli-reference#cli-flags"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/agent-sdk/permissions#allow-and-deny-rules"
        tier: 1
        pool: "Anthropic / platform+code.claude.com SDK docs"
  - claim: "The Agent SDK permissions page states the removal in request terms verbatim: 'The Bash tool definition is removed from the request' and 'Every tool definition is removed from the request.'"
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/agent-sdk/permissions#allow-and-deny-rules"
        tier: 1
        pool: "Anthropic / code.claude.com"
  - claim: "Empirically, --disallowedTools with bare names reduced the measured System tools bucket 18.1k -> 13.7k and the System tools (deferred) bucket 17.8k -> 10.3k in matched /context runs."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "claude -p \"/context\" --output-format json [--disallowedTools ...], Claude Code 2.1.232, run 2026-08-17"
        tier: 0
        pool: "direct tool output (this session)"
  - claim: "permissions.deny in settings.json and --disallowedTools share one rule syntax and one evaluation path, so bare-name removal applies to both."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/settings#permission-settings"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/permissions#manage-permissions"
        tier: 1
        pool: "Anthropic / code.claude.com"
produced_by: phase-2-falsification
---

# `disallowedTools` and `permissions.deny` — exact semantics

## The headline: the docs are NOT silent, and the answer is "it depends on the rule shape"

The dispatch anticipated that the docs might be silent here and asked to say so explicitly if they
were. **They are not silent.** Anthropic states the behavior in four places, one of which uses the
word *request*. The distinction is not between the two settings — it is between **bare** and
**scoped** rules, and that distinction is the whole answer.

## Statement 1 — the permissions page (fetched 2026-08-17)

`https://code.claude.com/docs/en/permissions`, section *Manage permissions*:

> Deny rules behave differently depending on whether they name a tool or scope a pattern within one.
> **A bare tool name like `Bash` removes the tool from Claude's context entirely, so Claude never
> sees it.** Bare-name removal applies to every tool except `EndConversation`: a deny rule can't
> remove it while any other tool remains, and an ask rule never prompts for it. **A scoped rule like
> `Bash(rm *)` leaves the tool available and blocks matching calls when Claude attempts them.**

Two more rows from the same page:

> `Bash(*)` is equivalent to `Bash` and matches all Bash commands. **As a deny rule, both forms
> remove the tool from Claude's context.**

> Deny and ask rules also accept glob patterns in the tool-name position. The pattern must match the
> full tool name: `"*"` matches every tool, and `"mcp__*"` matches every MCP tool across all servers.
> **A tool matched by a bare-name glob deny rule is removed from Claude's context**, the same as a
> bare tool name…

## Statement 2 — the CLI reference (fetched 2026-08-17)

`https://code.claude.com/docs/en/cli-reference#cli-flags`, `--disallowedTools` row:

> Deny rules. **A bare tool name removes the matching tools from Claude's context:** `"Edit"` removes
> Edit, `"*"` removes every tool, and `"mcp__*"` removes every MCP tool. A scoped rule such as
> `Bash(rm *)` leaves the tool available and denies only matching calls.

## Statement 3 — the Agent SDK permissions page, and it says *request*

`https://code.claude.com/docs/en/agent-sdk/permissions#allow-and-deny-rules` (fetched 2026-08-17).
**This is the strongest wording available and the one to quote in the skill:**

| Option | Effect (verbatim) |
|---|---|
| `allowed_tools=["Read", "Grep"]` | "`Read` and `Grep` are auto-approved. Other tools not listed here still exist and fall through to the permission mode and `canUseTool`." |
| `disallowed_tools=["Bash"]` | "**The `Bash` tool definition is removed from the request.** Claude does not see the tool and cannot attempt it." |
| `disallowed_tools=["Bash(rm *)"]` | "`Bash` stays available. Calls matching `rm *` are denied in every permission mode, including `bypassPermissions`. Other `Bash` calls fall through to the permission mode." |
| `disallowed_tools=["*"]` | "**Every tool definition is removed from the request.** Tool-name globs are supported in deny rules: `"*"` matches every tool and `"mcp__*"` matches every MCP tool across all servers." |

The same page places removal *before* the permission engine runs, which is why it is a payload effect
rather than a runtime guard:

> Check `deny` rules (from `disallowed_tools` and settings.json). If a deny rule matches, the tool is
> blocked, even in `bypassPermissions` mode. **Bare-name deny rules like `Bash` remove the tool from
> Claude's context before this evaluation begins**, so only scoped rules like `Bash(rm *)` are
> checked at this step.

## Statement 4 — settings.json `permissions.deny` is the same mechanism

`https://code.claude.com/docs/en/settings#permission-settings` (fetched 2026-08-17) documents `deny`
as "Array of permission rules to deny tool use… Tool names accept glob patterns: `"*"` denies every
tool and `"mcp__*"` denies every MCP tool." The SDK page above names its deny sources as "`from
disallowed_tools` **and settings.json**" in one breath, and the permissions page's rule-shape
paragraph is written about deny rules generally, not about one entry point. **So `permissions.deny`
with a bare name removes the definition exactly as `--disallowedTools` does.**

One caveat the skill must not lose: `disallowedTools` is **not** a settings.json key. It is a CLI
flag, an SDK option, and agent/plugin-agent frontmatter. In settings.json the key is
`permissions.deny`. (`settings.md`, 334 KB, contains zero occurrences of `disallowedTools`.)

## Empirical confirmation — Tier 0, run 2026-08-17

Claude Code **2.1.232**, model `claude-sonnet-5`, identical repo and session config, comparing
`claude -p "/context" --output-format json` runs:

| Run | System prompt | System tools | System tools (deferred) | Total |
|---|---|---|---|---|
| **A** baseline | 5.1k | **18.1k** | **17.8k** | 35.3k |
| **B** `--disallowedTools "Artifact" "Grep" "Glob"` (all prefix-loaded here) | 5.1k | **13.7k** | 17.8k | 30.9k |
| **C** `--disallowedTools` on 8 deferred built-ins + `"mcp__*"` | 5.1k | 18.1k | **10.3k** | 35.3k |
| **D** `--tools "Bash,Edit,Read"` | 4.8k | **6.1k** | *(bucket absent)* | 13.1k |

Readings, and the limits of each:

- **B is the decisive one.** Denying three *prefix-loaded* tools by bare name cut the `System tools`
  bucket by 4.4k and the session total by 4.4k. Bare-name deny removes prefix schemas. Confirmed.
- **C** cut the *deferred* bucket by 7.5k while leaving the prefix bucket untouched — bare-name deny
  reaches deferred definitions too, and the two buckets are independent.
- **B vs C together** show the rule shape, not the tool's bucket, is what determines removal.
- **D**: `--tools` produced the largest reduction of all (18.1k → 6.1k, and the `System tools
  (deferred)` line disappeared entirely). But `--tools` "doesn't affect MCP tools" per the CLI
  reference, so the disappearance of the whole deferred bucket is **not fully explained** by the
  documented behavior and may reflect MCP servers not having connected in that short `-p` run. Treat
  D's magnitude as **UNVERIFIED** and re-test before the skill quotes it.

The three runs used the same prompt and differed only in flags, so the deltas are attributable. They
are `/context`'s own **estimates** (the output is headed "Estimated usage by category"), not
tokenizer ground truth — see `RESEARCH-measurement.md`.

## The third lever: `--tools`

`https://code.claude.com/docs/en/cli-reference#cli-flags` (fetched 2026-08-17):

> `--tools` — Restrict which built-in tools Claude can use. Use `""` to disable all, `"default"` for
> all, or tool names like `"Bash,Edit,Read"`. … **The flag doesn't affect MCP tools; to deny those
> too, use `--disallowedTools "mcp__*"`.** A list that omits `EndConversation` doesn't remove it;
> `""` removes it only when no MCP tools remain.

This is an **allowlist over built-ins**, complementary to the denylist. For a session with many
built-ins and few needed, it is the shorter expression of the same trim.

## Summary table for the skill's trim actions

| Action | Removes schema from request? | Notes |
|---|---|---|
| `permissions.deny: ["Edit"]` (bare) | **Yes** | settings.json key; survives across sessions |
| `--disallowedTools "Edit"` (bare) | **Yes** | per-invocation; also SDK `disallowedTools` |
| `--disallowedTools "mcp__*"` | **Yes**, all MCP | bare-name glob |
| `--disallowedTools "*"` | **Yes**, everything | except `EndConversation` while others remain |
| `permissions.deny: ["Bash(rm *)"]` (scoped) | **No** | runtime block only; definition stays and is billed |
| `--tools "Bash,Edit,Read"` | **Yes**, for built-ins | allowlist; no effect on MCP tools |
| agent frontmatter `disallowedTools:` | **Yes** for that subagent | "Tools to deny, removed from inherited or specified list" |
| `alwaysLoad: true` | **No — the opposite** | forces a definition INTO the prefix |
| tool-search deferral | **No** | withheld from prefix; still sent in `tools` array |

**The one-line rule for the skill: a rule with parentheses is a guard; a rule without parentheses is
a deletion.**

## Falsification attempt — ran, and failed to break the claim

Per discipline, one Phase 2 query targeted the leading hypothesis directly (that the docs would be
silent and that deny would be call-blocking only): a search for `Claude Code "permissions" "deny"
bare tool name does NOT remove tool definition still in system prompt tokens`. It surfaced no
first-party or credible secondary source contradicting the documented behavior; the returned corpus
restated the bare-vs-scoped distinction. The two upstream issues that *look* contradictory
(#30480, #66073) concern the undocumented `disabledTools` key and are analyzed in
`RESEARCH-deferral-controls.md`. Empirical run B independently confirmed the doc claim, so the
falsification attempt failed in the direction that strengthens the finding.
