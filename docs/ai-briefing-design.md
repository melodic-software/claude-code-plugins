# ai-briefing — engine / profile / personal split (design record)

The design produced by the `design(ai-briefing)` gate (`melodic-software/medley#1392`, under wave-2
map `melodic-software/medley#1369`): how the in-repo `.claude/skills/ai-briefing/` skill splits into a
generic **`ai-briefing` engine plugin** plus an extracted, encapsulated **profile**. This is the
rationale + decision record; the executable work lives in the emitted issues below, whose bodies carry
the pre-baked decisions and stand alone (do not depend on this note being merged).

Decided 2026-07-12 with the owner (one decision at a time, interview mode). Empirical claims decay —
re-verify the medley-side surfaces named here before executing the cutover.

## The problem

The skill mixes three separable concerns: a generic AI-news aggregation **engine**, an **employer**
(SETWorks) tailoring layer, and the owner's **personal** collection state. Shipped as one unit, the
engine cannot be reused and the employer specifics cannot be relocated. The wave-2 content-separation
decision (map #1369) routes the employer content out via this design gate.

## Three tiers, three homes

| Tier | Content | Home |
|---|---|---|
| **Engine** (generic) | multi-wave collection (Chrome / Grok / Perplexity / RSS / GitHub), dedup, categorize/rank machinery, `retro` / `search` / `drift` actions, build pipeline (slides/html/pdf), per-profile loop, runner, state schema; the pragmatic-use ranking lens and apolitical filter as **overridable defaults**; provider logos; a neutral default brand | the **`ai-briefing` plugin** |
| **Employer profile** (SETWorks team) | audience framing (disability-services engineering team), the `setworks_impact` tech-stack lens (.NET/Aspire/Blazor, MSSQL, Duende IdentityServer, Azure + Cloudflare, MCP), SETWorks branding (logos, `brand.js` tokens, slide brand spec), the curated follow-list | a **named profile** `.claude/ai-briefing/setworks/` in a consuming project (interim: medley — see below) |
| **Personal** (owner) | accumulated collection state — `seen-items.json` dedup registry, per-run checklists, generated decks | `${CLAUDE_PLUGIN_DATA}`, keyed per profile |

## Profile mechanism

The plugin resolves a **named profile** via the profiled-folder convention (see the migration
playbook, "Extensibility contract v2.1 — the four seams", seam 2). Root files at
`.claude/ai-briefing/` are the default profile; `.claude/ai-briefing/<name>/` is a named profile that
overlays the default per key. Selection follows the convention-resolution ladder: one profile present
→ use it; several → an `active_profile` `userConfig` scalar or a `--profile <name>` argument; none →
the root default (an unprofiled, generic run). The plugin ships a re-runnable `setup` action that
interviews the consumer and scaffolds a profile (the contract requires it for any tracked-config seam).

**Why named-and-plural from day one:** a single fixed-path profile would force a file→folder reorg the
moment a second audience appears; the named form is identical effort and open-ended (drop a sibling
subfolder, no republish). This is the reference adoption of the profiled-folder convention.

## Ranking-policy defaults

The pragmatic-use ranking lens ("an engineer can use it next week → HIGH") and the apolitical filter
(drop partisan-only, keep industry-wide controversy) ship as the engine's **documented, overridable
defaults** — generically useful for any engineering-team audience, and a profile can override them per
the ladder. Only the SETWorks-specific `setworks_impact` stack lens is profile-only. Baking the two
policies as *documented* defaults (not silent behavior) keeps the editorial stance transparent and
flippable, per the "configurable-by-default, safe documented defaults" standard.

## Branding scrub

The generic plugin carries **no** employer branding. Neutral default brand tokens ship in the engine
so `--format slides|html` works out of the box; the SETWorks logos, `brand.js` tokens, and slide brand
spec move into the `setworks/` profile and overlay the default. Provider logos (Anthropic, OpenAI,
Google, …) stay in the engine — generic domain assets used nominatively, not employer branding.
Generated decks are machine output (`${CLAUDE_PLUGIN_DATA}`), never shipped in the plugin.

## Interim profile home — medley (cutover, not shed)

The SETWorks profile's **interim** home is medley: the cutover moves the employer content into
`.claude/ai-briefing/setworks/` (tracked, backed up, the convention's primary `${CLAUDE_PROJECT_DIR}`
team layer) and enables the `ai-briefing` plugin in medley's project settings. Chosen over a machine-
local user-scope overlay because tracked-and-backed-up beats machine-local, it is the canonical
convention path, the extraction is a reproducible in-repo `git mv` (not a manual copy into `~/.claude`),
and the content already lives in medley (a private repo) — a reorg, not a new exposure.

## Deferred — dedicated SETWorks repo (revisit trigger)

A dedicated private SETWorks-org repository consuming the plugin is the **long-term** profile home
(version-controlled and shareable across the SETWorks team, off the melodic-software org). Deferred by
owner decision 2026-07-12: not stood up in this program. Because the profile is an encapsulated named
folder, the migration is a clean tracked→tracked folder move with **no republish** of the plugin.

**Revisit when** any holds: the profile should be team-shared/owned outside melodic-software; a second
audience/profile is wanted; or the SETWorks content grows beyond what belongs in a personal umbrella
repo. Trigger action: file a `repo(setworks-briefing)` issue and move `.claude/ai-briefing/setworks/`
into it.

## Emitted issues

Sub-issue-linked under wave-2 map `melodic-software/medley#1369`:

- **`publish(ai-briefing)`** — author the generic engine plugin: the profiled-folder profile seam, the
  `setup` action, neutral default brand + provider logos, engine-default ranking policies, state to
  `${CLAUDE_PLUGIN_DATA}`. No employer content. `agent-ready`. Requires the `claude` CLI (publish gate)
  — route to a machine that has it.
- **`cutover(ai-briefing)`** (target: medley) — remove the in-repo skill, `git mv` the SETWorks content
  into `.claude/ai-briefing/setworks/`, enable the plugin in medley's project `.claude/settings.json`,
  re-qualify `/ai-briefing` references, and reconcile the medley-side surfaces coupled to the old skill
  paths (the `html-no-remote-fetch` deck exemption + CI path-excludes, `typos-config.md` vendored-
  content path, the html-artifacts-convention exemption). Blocked on `publish(ai-briefing)`; appended
  to sweep `melodic-software/medley#1323`.
