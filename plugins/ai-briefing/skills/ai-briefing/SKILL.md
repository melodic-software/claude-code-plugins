---
name: ai-briefing
description: "Build a source-backed AI industry briefing from official vendor publications, configured RSS feeds, GitHub releases, reputable secondary reporting, and user-supplied URLs. Use when: 'ai briefing', 'ai news', 'what's new in AI', 'catch me up on AI', 'prep for AI meeting', 'AI roundup', or 'generate AI slides'."
argument-hint: "[--profile <name>] [--since <1d|3d|7d|14d|30d>] [--providers <list>] [--extras|--no-extras] [--format markdown|slides|html] [--yes] [retro|search] [...args]"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`
Configured active profile: `${user_config.active_profile}`

## Purpose

Collect, deduplicate, rank, and present current AI-industry developments without depending
on organization-specific configuration. Markdown is the default output. HTML and PPTX are
explicit, optional outputs backed by the bundled deterministic build pipeline.

## Source and access policy

Use only interfaces that authorize automated access:

1. Official vendor blogs, documentation, changelogs, and release notes.
2. GitHub release pages and repository APIs.
3. RSS/Atom feeds listed by the selected profile.
4. Reputable secondary reporting, corroborated by a primary source when practical.
5. User-supplied public URLs and context.

Automated X/Twitter collection is disabled. Do not crawl, scrape, scroll, navigate, fetch,
or extract X pages through browser automation, DOM scripts, unofficial endpoints, or Grok.
Do not refresh following graphs or profile metadata. X's current terms expressly prohibit
crawling or scraping without prior written consent: <https://x.com/en/tos>.

If the user supplies an X URL, preserve it as user-provided citation metadata but do not
programmatically retrieve it. Ask for the relevant text when it is necessary, and seek a
non-X primary source for corroboration. This plugin does not configure a paid X API.

Playwright is allowed only for deterministic rendering and inspection of locally generated
HTML/PDF artifacts. It is not a collection provider.

## Arguments

| Flag | Default | Effect |
|---|---|---|
| `--profile <name>` | Configured `active_profile`, then `default` | Select a named profile for this invocation. |
| `--since <timeframe>` | 14d | Accept `1d`, `3d`, `7d`, `14d`, `30d`, or an ISO date. |
| `--providers <list>` | All | Limit collection to comma-separated provider buckets. |
| `--extras` / `--no-extras` | On | Include or omit robotics, science, and novel applications. |
| `--format <type>` | `markdown` | Emit markdown, HTML, or PPTX. Non-markdown formats require prior `/ai-briefing:setup --with-build-deps`. |
| `--yes` / `-y` | Off | Skip the pre-execution confirmation gate. Required for headless runs. |

Actions:

- Default: collect, deduplicate, rank, cite, and emit a briefing.
- `retro --meeting <N>`: record acted/noted/skipped feedback for an archived briefing.
- `search "<query>"`: search archived briefing markdown and return cited matches.

## Profile resolution

Files at `.claude/ai-briefing/` form the default profile. Each
`.claude/ai-briefing/<name>/` directory is a named profile overlay. Resolve the active
profile in this order:

1. `--profile <name>` for this invocation.
2. The rendered `${user_config.active_profile}` value when it is non-empty.
3. `default`.

Require a 1-63 character lowercase-kebab profile name and reject reserved Windows device
names before constructing any profile path.

Resolve that value in the skill before launching tools. Explicitly pass the result to every
build subprocess; do not assume plugin configuration is inherited by an arbitrary shell:

```bash
AI_BRIEFING_PROFILE="$PROFILE" node "${CLAUDE_PLUGIN_DATA}/runtime/build/run.js"
```

Never ask the consumer to export the variable globally.

A profile may contain:

| Artifact | Purpose |
|---|---|
| `sources.md` | Approved RSS/Atom feeds, official release pages, GitHub repositories, and user-supplied URLs. |
| `audience.md` | Optional stack/audience lens for impact annotations. |
| `brand.json` | Optional declarative deck brand overlay. |

## Default run

1. Parse and validate arguments. Reject unknown formats and malformed dates before any
   collection. Resolve the selected profile and read `sources.md` when present.
2. Unless `--yes` is present, show the timeframe, provider scope, source classes, selected
   profile, and requested output format. Ask for confirmation before outbound collection.
3. Search official vendor publications and GitHub releases first. Read configured feeds and
   permitted user-supplied non-X URLs. Use reputable secondary reporting to fill gaps and
   corroborate claims. Record source URL, publisher, publication date, and retrieval date.
4. For every item, require at least one working source URL. Prefer the primary announcement;
   label claims that remain secondary-only. Exclude content outside the requested window.
5. Deduplicate by canonical URL and normalized event identity. Merge corroborating sources
   into one item rather than repeating the same announcement.
6. Categorize into provider buckets and rank by practical impact, availability, novelty,
   source confidence, and relevance to `audience.md`. Never invent details or silently turn
   rumors into facts.
7. Write the current markdown briefing and update the seen-item registry under the selected
   profile's `${CLAUDE_PLUGIN_DATA}` state directory. Keep tracked profile configuration in
   the project; never write curated configuration into plugin data.
8. For `--format html` or `--format slides`, require the optional build tree installed by
   `/ai-briefing:setup --with-build-deps`. Run the staged build pipeline against the emitted
   markdown with `AI_BRIEFING_PROFILE="$PROFILE"` set on the launched process. Playwright may
   open only generated local HTML for PDF rendering and layout validation. Surface missing
   prerequisites with the exact setup command; do not silently fall back to another browser
   provider.
9. Report collected, excluded, deduplicated, and secondary-only counts plus the output path.
   Make warnings visible, including unreachable sources and missing optional build tooling.

## Output contract

The markdown briefing contains:

- Run metadata: profile, window, retrieval time, and source classes used.
- Provider sections with HIGH, MEDIUM, and LOW tiers.
- Item title, concise evidence-backed summary, practical impact, publication date, and
  source links.
- A visible caveats section for inaccessible sources, secondary-only claims, and gaps.
- An optional EXTRAS section when enabled.

Machine-local state and generated artifacts live under
`${CLAUDE_PLUGIN_DATA}/<profile>/`. Tracked source, audience, and brand configuration lives
under `.claude/ai-briefing/[<profile>/]` in the consumer repository.

## Quality gates

- Every factual item has a source URL and date.
- Primary sources are preferred and clearly distinguished from secondary reporting.
- No automated X access occurs, including through browser tools or indirect DOM scripts.
- The same event appears once, with corroborating links attached.
- Missing dependencies and partial collection are visible; no black-box degradation.
- HTML/PDF browser use is local-render-only.

## References

- `references/audience-defaults.md` — default ranking lens and profile overlay.
- `references/build-pipeline.md` — deterministic HTML/PDF/PPTX generation and validation.
- `references/slide-generation.md` — slide structure and optional build prerequisites.
