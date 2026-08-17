---
outcome: research-complete
tier: A
date: 2026-08-17
---

# Findings — startup context budget

Nine dispatched research runs plus first-hand measurement on this machine. Every figure below is a
**snapshot of Claude Code CLI v2.1.232 on 2026-08-17**, recorded as evidence for a design decision.
Per [DESIGN-PRINCIPLES](research/DESIGN-PRINCIPLES.md), none of these
values may be shipped as skill content — the skill measures the consumer's own machine and cites the
mechanism, never the number. The full research corpus, including per-claim citation sidecars, lives
in [research/](research/).

## Provenance and how to grade it

Evidence sits in four tiers, and they are not equally independent:

- **Tier 0** — the installed binary (read and executed), and live `/context` output. The strongest.
- **Tier 1** — `code.claude.com`, the changelog, `raw.githubusercontent.com/anthropics/claude-code`.
- **Tier 2** — third-party write-ups.

**`code.claude.com` is one publishing pool however many pages are cited.** Multi-page citation from
it is not multi-source corroboration. Genuine independence here comes from binary inspection, the
GitHub raw repo, and executed measurement.

Two egress limits shaped the run: `www.aihero.dev` and `claude.com` are blocked from this
environment, so the course's own figures and the Anthropic "80% system-prompt reduction" blog post
could not be read first-hand. The latter is independently first-party at **changelog v2.1.154**,
which is the stronger citation anyway.

## The measured result

Method: `claude -p "/context"` A/B differencing against a fixed baseline. Free, exit 0, repeatable.

| Run | `System tools` | Delta |
|---|---|---|
| baseline | 18.1k | — |
| deny `Workflow` (bare name) | 10.2k | −7.9k |
| deny `Artifact` (bare name) | 13.7k | −4.4k |
| deny both | 5.8k | −12.3k |
| deny `Bash(rm *)` (scoped) | 18.1k | **0** |

Deltas are **exactly additive** (7.9 + 4.4 = 12.3), so attribution by differencing is compositional.
Two tools are **68% of the entire non-deferred tool pool**.

| Run | `Skills` | `Custom agents` |
|---|---|---|
| baseline (65 plugins, 185 skill rows, 131 collapsed to `< 20`) | 9.9k | 1.5k |
| 3 skills set `off` via `skillOverrides` | 9.9k | — |
| **45 of 65 plugins disabled** | **10k** | **861** |
| `--safe-mode` (14 skill rows, 0 collapsed) | 1.9k | — |

## The five mechanism findings

**1. Rule *shape* decides whether a schema ships.** A **bare tool name** in `permissions.deny` or
`--disallowedTools` removes the definition from the request — the Agent SDK permissions page states
it in request terms outright. A **scoped** rule (`Bash(rm *)`) is a runtime guard whose schema still
ships and is still billed every turn. Confirmed Tier 0 and reproduced here.

**2. Deferral does not shrink the request.** `defer_loading` controls what enters the context window,
not what is sent; the full schema goes out in the `tools` array every turn so the cached prefix stays
stable. A deferred tool is out of your context window but still in your request. This **inverts the
premise the course's headline lever rests on**.

**3. The skill listing is hard-capped (~1%), so disabling skills saves nothing while over the cap.**
Disabling 45 of 65 plugins moved the row by zero; the survivors expanded into the freed budget. Five
independent confirmations. What fewer plugins actually buys is **routing accuracy**, not tokens —
that is the honest benefit to offer.

**4. Custom agents are *not* capped** — the same run cut them 1.5k → 861, roughly proportional. But
`permissions.deny: ["Agent(<name>)"]`, which the sub-agents docs present as disabling an agent,
**leaves the agent's description in the startup payload unchanged** (verified against a control deny
that did move the deferred row). The working lever is plugin-level disable.

**5. `System tools` has listed skill-frontmatter tokens subtracted from it**, so removing skills makes
it rise with no tool changing state. Only compare it between runs whose skill listing is identical.

## Per-lever disposition

| Lever | Verdict |
|---|---|
| Bare-name deny (`permissions.deny`) | **Removes weight.** Largest available lever. |
| `disableWorkflows` / `CLAUDE_CODE_DISABLE_WORKFLOWS` | **Removes weight** — wired to the schema-removal path, Tier 0 + request-body diff. |
| `disableArtifact` family | **Removes weight**, and uniquely also clears the three artifact skills; deny-based levers remove the tool but leave those skills listed. |
| `includeGitInstructions: false` | **Removes ~2.4k** — but lands in `System tools`, not `System prompt`, because the commit/PR instructions ride in the **Bash tool description**. |
| `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` | **5.1k → 1.8k**, but a **measured no-op on claude-opus-5**, where the lean prompt is already default. Advice must branch on session model. Distinct from `CLAUDE_CODE_SIMPLE` — the binary registers them as two separate env vars (verified in the v2.1.232 env map). |
| `skillOverrides` | **Works but saves nothing** while the listing is over cap. Only lever reaching claude.ai-synced skills. |
| Plugin disable | **Saves on agents, not on skills.** Primary benefit is routing accuracy. |
| Scoped deny rules | **Blocks without saving.** |
| `--exclude-dynamic-system-prompt-sections` | **Net zero** — relocates ~0.6k into the first user message. |
| Custom output style, `keep-coding-instructions: false` | **Net-negative** — buys ~1k by discarding built-in software-engineering instructions. |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | **Increases** payload — forces every MCP tool upfront; `ENABLE_TOOL_SEARCH` cannot override it. |

## Corrections to the source material

| Course claim | Status at v2.1.232 |
|---|---|
| `/context` gives only category totals; you need a request logger | **Outdated** — it itemises per-skill and per-agent with a `Source` column, and per-tool/per-server for MCP |
| Disabling deferred MCP tools is a large saving | **Misleading** — deferral never shrank the request |
| Trimming skills reclaims their tokens | **False while over cap** |
| The 17.9k → 3.5k drop is a settings mystery | **Explained** — two tool schemas are ~12.3k of it |

Its arithmetic also does not reconcile (categories sum to ~64k against a ~23k headline; the headline
delta is smaller than the MCP delta alone). Do not reproduce its tables. What it gets right and we
keep: the **framing** — this maximises the smart zone, and is not a cost-minimisation exercise.

## Corrections owed to this repository

1. **`docs/topics/context-engineering-claude-5/design/checks-and-sweep.md:291`** adopts
   `claude --safe-mode` + `CLAUDE_CONFIG_DIR` as clean-room comparison. Neither is: safe mode leaves
   all bundled skills loaded, and a clean config dir does not unload them either.
2. **`plugins/claude-config/skills/unhobble/SKILL.md`** states `CLAUDE_CODE_SIMPLE=1` "is
   undocumented and may vanish" and describes it as stripping Claude Code's built-in prompts. Wrong
   on both counts: **it is documented** — its own row in the official env-vars reference, plus the
   CLI equivalent `--bare` — and the binary shows simple mode disables fetches, keychain reads and
   `CLAUDE.md` auto-discovery, while the prompt-stripping lever is the **separate** sibling var
   `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT` (both registered independently in the v2.1.232 env map). The
   gotcha needs rewriting against both facts.
3. **`docs/conventions/permission-rule-hygiene/README.md`** block-quotes a "Starting August 14, 2026"
   passage no longer at its cited URL (now a version floor, v2.1.228 / v2.1.233 native Windows), and
   reasons only about *loosening* permissions — nothing on tightening, which is what this skill does.
4. **`docs/topics/context-engineering-claude-5/design/coverage-matrix.md:30`** marks S7 "deferred tool
   loading is unowned" as a `PARTIAL` gap. This work closes it.
5. **`discovery` plugin bug:** `skills:` preload did not fire for `discovery:researcher` in **all nine**
   runs. Each recovered by reading `SKILL.md` from disk, so the discipline ran — but the echoed
   preload sentinel proves only that the agent read the file, **not that preload worked**. Any gate
   treating a matching token as proof of preload is unsound. Worth its own issue.

## Unresolved

- **Whether the Agent SDK exposes `get_context_usage`.** A structured object with exact integers and
  a `free|buffer|deferred|used` enum exists in the binary behind the control protocol. If reachable,
  it eliminates the markdown-parsing brittleness entirely. **Resolve before committing to a parser.**
- **Whether HTTP/Streamable-HTTP MCP tools are actually deferred at 2.1.232.**
  `anthropics/claude-code#40314` reported 120K tokens upfront at v2.1.86, closed as not planned; no
  one could confirm a fix. Argues for measuring deferral per session rather than trusting the default.
- **Whether a `PreToolUse` `ask` decision survives `bypassPermissions`.** Documented silence — the
  docs enumerate what still prompts there and hook decisions are absent from that list.
- **Cloud/web surface behaviour.** `disableClaudeAiConnectors` is inert there and `deniedMcpServers`
  URL patterns do not match because the proxy rewrites URLs.
- **`skillOverrides` documentation status** — two runs disagree on whether it appears in official
  settings docs. Verify before the skill depends on it.

## Traps for the measurement engine

- `/context`'s format carries **no stability guarantee in either direction** — it is not presented as
  an interface. Materially changed at v2.0.74, v2.1.0, v2.1.129, v2.1.139, v2.1.216.
- `--output-format json` returns the same markdown as a string in `.result`.
- Skill token cells use a different formatter (`~<int>` or literal `< 20`) from every other table.
- Unredirected stdin prepends `Warning: no stdin data received`, breaking `JSON.parse`.
- **There is no `disallowedTools` key in `settings.json`** — CLI-only. Emitting one writes a
  silently-ignored key. Persistent config must use `permissions.deny`.
- **Multiple CLI installs on one machine** (this one has v2.1.232 and v2.1.42, whose category list
  differs). Pin and report which binary was measured.
- Headless `/context` is **undocumented** as a `-p`-capable command. Load-bearing but unsanctioned:
  degrade gracefully and say so.
- Widespread "deny doesn't save tokens" advice traces to `disabledTools` — a key that has never
  existed (`#30480`, `#66073`, both closed not-planned). Not counter-evidence.
