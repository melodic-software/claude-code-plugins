---
topic: plugins-mcp-context-budget
section: doctor-delegation-seam
abstract: The bundled /doctor skill (a full setup checkup since v2.1.205) already owns finding unused skills/MCP servers/plugins versus their context cost and disabling them, so a new skill must delegate that check and can only differentiate on scope, headlessness, per-plugin attribution and CI use.
claims:
  - claim: "/doctor is a bundled skill, labelled as such in the commands reference, and it survives the disableBundledSkills kill switch."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/commands (/doctor row opens '**[Skill](/docs/en/skills#bundled-skills).**')"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/skills (bundled skills list; disableBundledSkills 'disables every bundled skill except /doctor')"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "binary-extracted command registration: nd({name:'doctor',aliases:['checkup'],survivesBundledKillSwitch:!0,...})"
        tier: 0
        pool: "installed Claude Code v2.1.232 binary"
  - claim: "v2.1.205 (July 8, 2026) is the release that made /doctor a full setup checkup that can fix issues, with /checkup as its alias; before v2.1.205 it was a read-only diagnostics screen."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/changelog (Update label 2.1.205, July 8, 2026)"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/debug-your-config ('Before v2.1.205, /doctor opened a read-only diagnostics screen')"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
        tier: 1
        pool: "anthropics/claude-code GitHub repository"
  - claim: "/doctor Check 1 already inventories unused skills, MCP servers and plugins against their context cost and proposes scope-correct disable edits; Check 6 already summarises always-resident context by component."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "binary-extracted /doctor bundled-skill prompt, '## Check 1 -- unused skills, MCP servers, and plugins' and '## Check 6 -- context-heavy extensions'"
        tier: 0
        pool: "installed Claude Code v2.1.232 binary"
      - url: "https://code.claude.com/docs/en/commands (/doctor row: 'Finds unused skills, MCP servers, and plugins versus their context cost')"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/debug-your-config ('unused extensions')"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
produced_by: phase-1-phase-2-phase-3
---

# Q5 — The bundled `/doctor` skill: what it claims, what it doesn't, and the delegation seam

Docs fetched **2026-08-17**. The `/doctor` skill body is **Tier 0**: extracted from the installed
`claude` binary (v2.1.232) at `node_modules/@anthropic-ai/claude-code/bin/claude.exe`, 2026-08-17.
All indented quotes below are verbatim from that extraction unless a URL is given.

## Status: it IS a bundled skill, and it is privileged

The commands reference marks it explicitly — the `/doctor` row **opens** with
`**[Skill](/docs/en/skills#bundled-skills).**`
(<https://code.claude.com/docs/en/commands>, fetched 2026-08-17).

> "Claude Code includes a set of bundled skills, such as `/doctor`, `/code-review`, `/batch`,
> `/debug`, `/loop`, and `/claude-api`. […] Bundled skills are available in every session. To turn
> them off, use the `disableBundledSkills` setting, **which disables every bundled skill except
> `/doctor`**." — <https://code.claude.com/docs/en/skills> (fetched 2026-08-17)

Tier-0 registration from the binary confirms the privilege and the invocation model:

```js
nd({ name:"doctor", aliases:["checkup"], isEnabled:()=>!Y.DISABLE_DOCTOR_COMMAND,
     survivesBundledKillSwitch:!0, requires:{workspace:!0}, terminalOriented:!0,
     userInvocable:!0, disableModelInvocation:!0, progressMessage:"running checkup", ... })
```

**`disableModelInvocation: true`** — Claude cannot trigger `/doctor` on its own; only the user can.
This is directly relevant to delegation: a new skill **cannot invoke `/doctor` as a tool call**. It
can only *instruct the user to run it*, or reimplement the parts it needs. To hide it entirely:
`DISABLE_DOCTOR_COMMAND` env var, or a `skillOverrides` entry.

## Which version made it a bundled skill

**v2.1.205, July 8, 2026.** Two independent first-party artifacts agree:

- Changelog, `<Update label="2.1.205" description="July 8, 2026">`:
  "`/doctor` is now a full setup checkup that can diagnose and fix issues; `/checkup` is its alias"
  (<https://code.claude.com/docs/en/changelog>, fetched 2026-08-17; identical text at
  <https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md>, fetched 2026-08-17).
- "Before v2.1.205, `/doctor` opened a read-only diagnostics screen and pressing `f` sent the report
  to Claude to fix." (<https://code.claude.com/docs/en/debug-your-config>, fetched 2026-08-17)

The related `CLAUDE.md` trim check (Check 3) arrived one release later: **v2.1.206**.

**Caveat on wording:** the changelog says "full setup checkup that can diagnose and fix", not
literally "is now a bundled skill". The *skill* framing is attested by the current commands
reference and by the binary registration. So: v2.1.205 is the release where `/doctor` became the
prompt-driven checkup it is now. Whether the internal "skill" classification landed on exactly that
release, or slightly later, I could not confirm from the changelog text alone.

## What `/doctor` claims to do — its own check list (Tier 0)

The skill prompt contains exactly these sections:

```
## Ground rules
## Data sources (all local -- the ONLY permitted network access is check 7's read-only
                 latest-version lookup, and even that is skipped in essential-traffic mode)
## Check 0 -- setup health (installation, settings, agent definitions)
## Check 1 -- unused skills, MCP servers, and plugins
## Check 2 -- LOCAL CLAUDE.md dedup and contradictions
## Check 3 -- trim derivable content from checked-in CLAUDE.md files
## Check 4 -- migrate always-loaded CLAUDE.md content to lazy loading
## Check 5 -- slow hooks
## Check 6 -- context-heavy extensions
## Check 7 -- Claude Code version
## Check 8 -- auto mode as the default permission mode
## Check 9 -- pre-approve frequently denied read-only commands
## Report format
## Steps
```

### Check 1 — the overlapping check, in detail

> "For each user-installed skill, MCP server, and plugin, collect its lifetime usage total […] and
> whether it was used in the scan window (`lastUsedAt` inside the window, plus transcript hits […]
> transcripts are the ONLY window signal for MCP servers, which have no counter), plus estimated
> always-in-context cost."

Its **data sources** (all local):

- **`~/.claude.json`**: `skillUsage` (name → `{usageCount, lastUsedAt}`), `pluginUsage`
  (`"<name>@<marketplace>"` → `{usageCount, lastUsedAt}`), `numStartups`. `usageCount` is a
  **lifetime** total, never windowed.
- **Session transcripts**: `~/.claude/projects/<sanitized-cwd>/*.jsonl`, "the ~50 most-recently-
  modified files across ALL project dirs".
- **Config**: the settings cascade, `~/.claude.json` `mcpServers`, `.mcp.json`, `hooks` keys.
- **Content for size estimates**: skill dirs and every loaded CLAUDE.md.

Two signal-quality subtleties it already handles, which a competing implementation would have to
rediscover:

> "`pluginUsage` entries are SEEDED with `lastUsedAt` = now on install/enable and at session-start
> backfill, and `lastUsedAt` is refreshed on re-enable even with zero usage, so for plugins treat
> `lastUsedAt` as window-usage evidence only when `usageCount` > 0 or transcripts corroborate it"

> "MCP tools are named `mcp__<server>__<tool>`; […] The `<server>` segment is the NORMALIZED server
> name — any char outside `[a-zA-Z0-9_-]` becomes `_` […] plugin servers keyed
> `plugin:<plugin>:<server>` appear as `mcp__plugin_<plugin>_<server>__`, and claude.ai connectors as
> `mcp__claude_ai_<connector>__` — match transcripts against the normalized form, but always issue
> disables with the original configured name/key."

And it explicitly refuses to count deferred MCP tools as context cost (quoted in full in
`RESEARCH-mcp-enablement-deferral.md`).

Its **verdict policy**: zero invocations in the window → recommend disabling. Borderline → still take
a position. "Not touching" is reserved for exactly two cases: **bundled/built-in skills and anything
enabled by managed policy** ("user-installed extensions only"), and items with real observed usage.

Its **disable mechanics** are scope-correct (see `RESEARCH-plugin-enablement-scopes.md` and
`RESEARCH-mcp-enablement-deferral.md`).

### Check 6 — context-heavy extensions, verbatim in full

> ## Check 6 -- context-heavy extensions
>
> Summarize estimated always-resident context by component: each CLAUDE.md file, the skill/command
> listing total (vs its ~1% budget), non-deferred MCP tool schemas, and plugins' resident
> contributions. Deferral rules from check 1 apply -- deferred MCP tools are ~0. Call out the largest
> few. Recommend `/context` for the exact live measurement; your figures are disk-based estimates.

## What `/doctor` explicitly does NOT do — the delegation seam

Each of these is stated or structurally implied by the extracted prompt and the docs:

1. **It cannot be model-invoked.** `disableModelInvocation: true`. A new skill cannot call it.
2. **It does not measure live context.** Its own words: "your figures are **disk-based estimates**";
   it defers to `/context` for "the exact live measurement". It never reads the live request.
3. **It does not use `claude plugin details`.** Nothing in the prompt references that command, even
   though it is the product's own per-plugin token-cost tool and is headless-capable. **This is the
   clearest differentiation opportunity.**
4. **It is interactive and terminal-oriented.** `terminalOriented:!0`, `requires:{workspace:!0}`, and
   my Tier-0 probe confirms `claude -p "/doctor"` did not produce a checkup. It is not a CI/headless
   surface.
5. **It excludes runtime state by design.** Check 0: "Runtime state only a live app can see (MCP
   servers failing to connect, plugin load errors, sandbox issues) is out of scope for this check: if
   symptoms point there, send the user to `/mcp`, `/plugin`, or `/sandbox` instead of guessing."
6. **It never proposes disabling bundled skills or managed-policy items.** "user-installed extensions
   only".
7. **Its window is fixed at ~50 transcripts** across all project dirs — not configurable, not
   per-project scopable, and it explicitly reports the window it covered rather than accepting one.
8. **It does not model prompt-cache cost.** Nothing in the prompt mentions cache invalidation,
   `/reload-plugins --force`, or the deferred-vs-prefix cache distinction — even though that is the
   real cost of applying its own recommendations mid-session.
9. **It does not touch per-project `/mcp disable` repetition.** It notes the per-project limitation
   and tells the user to repeat it manually.
10. **No network access** except the version lookup.

## Recommended delegation posture for the new skill

**Delegate, don't duplicate:** unused-item detection, usage counters, transcript scanning, verdict
policy and scope-correct disable edits are all Check 1's, already carefully specified. Re-deriving
them will produce a worse version of the same thing (especially the `pluginUsage` seeding trap and
the MCP tool-name normalisation).

**Differentiate on what Check 1 and Check 6 structurally cannot do:**

- **Per-plugin measured cost via `claude plugin details <name>`** — headless, uses the `count_tokens`
  API, and gives an `Always-on` figure per plugin plus a component inventory. `/doctor` uses
  character estimates instead.
- **Headless / CI operation.** `claude plugin list --json`, `claude plugin details`, and
  `claude -p "/context"` all run non-interactively (Tier-0 verified). `/doctor` does not.
- **A reproducible baseline artifact.** `/doctor` produces a one-shot conversational report;
  nothing persists a measured startup-payload baseline that can be diffed across commits.
- **Prompt-cache-aware sequencing** — batching enablement edits, and routing application through
  `/reload-plugins` (with its `--force` gate) rather than mid-session toggles.
- **Cross-project scope reasoning** — resolving *which* settings scope currently carries each `true`,
  which `/doctor` only handles for the item it is about to change.

**Concrete seam:** the new skill should say, in its own body, that unused-extension detection is
`/doctor`'s Check 1 and instruct the user to run `/doctor` for it, while the skill itself owns
measurement, baselining and headless/CI reporting.

## Source-quality note

Several third-party pages surfaced in Phase 3 search for this question (wmedia.es, mcp.directory,
computingforgeeks) are unattributed aggregator/SEO content and are **not cited** as corroborators
here per the discipline's source-quality red flags. One of them asserts that an active plugin's
"skills, agents, hooks, and above all its MCP servers weigh on your context window turn after turn" —
which **contradicts the primary** on two counts (hooks are harness-only; MCP tools are deferred).
Recorded as a conflict in `RESEARCH-methodology.md`; the primary wins.
