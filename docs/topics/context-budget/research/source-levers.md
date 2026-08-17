# Source coverage — every lever the course material names

Source: two lessons pasted by the operator (AI Hero / Matt Pocock, "Your Starting Context" and
"Killing Bloat"). This file is the completeness check: each row must be resolved by a research run
or explicitly marked unresolvable before the design is called final. Nothing from the source is
dropped for being inconvenient.

## The source's own measured baseline

His "default config" run vs his "own config" run, both from `/context`:

| Category | Default | His config | Delta |
|---|---|---|---|
| System prompt | 3k | 2k | −1k |
| System tools | 17.9k | 3.5k | **−14.4k** |
| MCP tools (deferred) | 24.5k | 192 | **−24.3k** |
| System tools (deferred) | 16.9k | 9.2k | −7.7k |
| Skills | 2k | 1.1k | −0.9k |
| **Reported total** | **~23k** | **~6.6k** | **−16.4k** |

**Two arithmetic problems in the source, both worth naming rather than repeating.**

1. The categories in the default column sum to ~64k, not the ~23k headline. Deferred pools are
   evidently not counted toward the headline the way the table implies. Any skill quoting these
   numbers inherits the inconsistency — so the skill must report what `/context` actually returns
   at the consumer's own version, never transcribe these figures.
2. The headline delta (−16.4k) is smaller than the MCP delta alone (−24.3k), which is only
   coherent if deferred pools are excluded from the headline. This is the single most important
   thing to settle: **does a deferred tool cost prefix tokens at all?** If deferred tools are
   effectively free, then disabling connectors buys far less than the source implies, and the
   headline lever of lesson 1 is largely theatre.

**The unexplained 14.4k.** `System tools` — the non-deferred pool — drops from 17.9k to 3.5k purely
from restoring his `settings.json`. The source never says which key does that. This is the highest
value unknown in the entire course, and per-tool attribution is the only thing that can answer it.

## Lever inventory

| # | Lever | Source | Status |
|---|---|---|---|
| L1 | claude.ai connectors (Figma, Gmail, Google Calendar, Google Drive, Slack, Todoist, Zapier) | lesson 1 + 2 | research: connectors |
| L2 | Workflows / the `Workflow` tool | operator's list | research: workflows |
| L3 | Bundled / built-in skills | operator's list | research: bundled-skills |
| L4 | Artifacts — `Artifact` tool + artifact-design / -diagramming / -capabilities skills | operator's list | research: artifacts |
| L5 | Unused tool definitions generally | lesson 2 + operator | research: tool-definitions |
| L6 | Plugins (enable/disable, per scope) | operator's addition | research: plugins-mcp |
| L7 | Project MCP servers via `.mcp.json` — distinct from L1 connectors | inferred | research: plugins-mcp |
| L8 | The system prompt itself — Environment block, Context-management block, recent git commits | lesson 2 | **UNASSIGNED** |
| L9 | Custom agents (own `/context` row; 1.5k measured here) | not in source | **UNASSIGNED** |
| L10 | Memory files / CLAUDE.md | not in source | covered by `/doctor` + `audit-instructions` |
| L11 | Output styles | not in source | **UNASSIGNED** |
| L12 | Context-injecting hooks | not in source | covered by PLUGIN-PHILOSOPHY "Classifying a hook" |

L8, L9 and L11 have no research run assigned. L8 matters most: the source explicitly points at the
Environment and Context-management blocks and at recent git commits being injected, and this
marketplace's `unhobble` skill already records `CLAUDE_CODE_SIMPLE=1` as an undocumented,
out-of-contract way to strip built-in prompts. Whether any *supported* lever exists is unresolved.

## Named tools the source calls out as unknown-to-users

`CronCreate`, `DesignSync`, `EnterPlanMode`, `Workflow`, `Artifact`, `Bash`.

Observed in this session's own harness: `CronCreate`, `DesignSync` and `EnterPlanMode` are all in
the **deferred** pool (schemas not loaded until `ToolSearch` fetches them), whereas **`Workflow` is
a prefix tool carrying one of the largest descriptions in the payload** — several hundred lines of
orchestration guidance, pipeline patterns and worked examples. That asymmetry supports the
operator's instinct to name workflows as a top trim candidate, and it is a measurement the skill
should make rather than assert.

The source also flags "redundant text explaining commit message formats, PR templates, and feature
flags" inside tool descriptions. Confirmed present in this session's `Bash` tool description
(commit trailers, PR body footer) — but that is vendor-owned text with no consumer lever, so it
belongs in the report as *unaddressable weight*, never as an action.

## Method the source uses, and this skill's position on it

- **Request logger (an intercepting proxy that dumps the wire payload).** Gives true per-tool bytes.
  Rejected as a shipped component — it intercepts provider traffic and writes full system prompts
  to disk, which fails the plugin-acceptance security review's deny-by-default stance on egress.
  Document as an optional operator-run method; never ship it.
- **Rename `settings.json` / `skills/` to `-backup`.** Course choreography for a common baseline,
  not a durable capability. The supported equivalent is `claude --safe-mode` / `CLAUDE_CONFIG_DIR`
  clean-room comparison, which the fleet already names as the native-first inventory route.
- **`/context` as the meter.** Adopted, and stronger than the source knew: at v2.1.232 it already
  itemizes per-skill and per-agent tokens with a `Source` column. The source's claim that it only
  gives category totals is out of date.

## Framing to preserve

The source is explicit that this is **not** cost minimisation — it is maximising the smart zone,
the part of the window where the model reasons. The skill's report must lead with reclaimed
reasoning space, not dollars saved. This aligns with the marketplace's existing
`PLUGIN-PHILOSOPHY.md` "Instruction economy" section and with `context-guard`'s zone vocabulary.
