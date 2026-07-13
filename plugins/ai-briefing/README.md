# ai-briefing

A Claude Code plugin that aggregates AI-industry news into a ranked briefing. It runs
multi-wave collection (Chrome/X, optional Grok preload, Perplexity, RSS, GitHub releases),
deduplicates and categorizes across provider buckets, and presents the result as markdown,
a self-contained HTML deck, or a PPTX. It is a **generic engine**: the curated inputs and
branding for a given audience live in a **profile** in your project, not in the plugin.

## Skills

| Skill | Invoke | What it does |
|---|---|---|
| `ai-briefing` | `/ai-briefing:ai-briefing` | Runs a briefing: collect → dedup → categorize → rank → emit. Also `retro --meeting <N>`, `search "<query>"`, and `drift` actions. |
| `setup` | `/ai-briefing:setup` | Scaffolds or reconfigures a profile (curated follow-list, optional branding, optional stack lens) and installs runtime dependencies. Idempotent. |

## Getting started

1. Enable the plugin, then run `/ai-briefing:setup`. It scaffolds a profile under
   `.claude/ai-briefing/` (seeding the follow-list from a bundled neutral list of public
   vendor accounts) and installs the runtime dependencies.
2. Tailor `following-list.json` in that profile, or run
   `/ai-briefing:ai-briefing --refresh-following` to scrape your own following graph.
3. Run `/ai-briefing:ai-briefing` for a briefing. Add `--format html` or `--format slides`
   for a deck (the build dependencies are heavier — `setup` installs them on request).

## Profiles (audience / deployment variants)

Files at `.claude/ai-briefing/` are the **default profile**; each
`.claude/ai-briefing/<name>/` subfolder is a **named profile** that overlays the default
per key. A profile carries the curated `following-list.json`, an optional `brand.js`
overlay (org name, tagline, logos, theme), and an optional stack lens that turns on the
per-item `impact` tag. Select the active profile when several exist via the `active_profile`
plugin option or a `--profile <name>` argument, and export `AI_BRIEFING_PROFILE=<name>` for
the runner/build scripts. With no profile, the engine runs against the bundled neutral seed
and default brand.

## Configuration

| Option | Type | Purpose |
|---|---|---|
| `active_profile` | string | Which profile to use when more than one exists. Unset resolves automatically. |

Rankings ship as **documented, overridable defaults**: a pragmatic-use ranking lens (bias
HIGH toward things an engineer can use next week) and an apolitical filter (drop partisan-only
content, keep industry-wide controversy). A profile can refine or replace them.

## State and dependencies

Machine-local run state — the seen-items dedup registry, per-run artifacts, and generated
decks — persists under `${CLAUDE_PLUGIN_DATA}`, keyed per profile, and survives plugin
updates. The plugin cache is read-only, so runtime dependencies also persist under
`${CLAUDE_PLUGIN_DATA}` (installed by `/ai-briefing:setup`); the runner and build scripts are
invoked with `NODE_PATH` pointed there. No curated configuration is ever written to the data
directory — that flows through the profile in your project.

Grok Build is optional — the briefing never requires it; without it, Chrome Wave 1 is the
full path (install: <https://x.ai/cli>).
