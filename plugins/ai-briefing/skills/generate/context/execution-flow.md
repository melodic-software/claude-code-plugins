# AI Briefing Execution Flow

This runbook supports the active `generate` skill. The skill's source/access policy is
authoritative.

## 0. Parse and validate

1. Parse profile, timeframe, provider scope, extras, format, and `--yes`.
2. Reject unknown flags, malformed dates, and unsupported formats before collection.
3. Resolve profile precedence: invocation `--profile`, the rendered
   `${user_config.active_profile}` skill value, then `default`.
4. Read the selected profile's `sources.md`, `audience.md`, and declarative `brand.json` when present.
5. For HTML or slides, verify `${CLAUDE_PLUGIN_DATA}/runtime/build/` exists. If not, stop
   with `/ai-briefing:setup apply install-build-deps`.

## 1. Confirmation gate

Unless `--yes` is present, display:

- selected profile and timeframe;
- provider scope and source classes;
- configured source count;
- requested output format;
- whether the optional build toolchain is ready.

Wait for confirmation before outbound collection. Headless callers must pass `--yes`.

## 2. Collect from authorized interfaces

Use this priority order:

1. Official vendor documentation, release notes, changelogs, and blogs.
2. GitHub releases and repository APIs.
3. Profile-configured RSS/Atom feeds.
4. Reputable secondary reporting.
5. User-supplied non-X URLs that permit automated access.

For every candidate record the canonical URL, publisher, publication time, retrieval time,
title, and evidence excerpt or summary. Set explicit timeouts for outbound requests and make
partial failures visible.

Automated X/Twitter access is prohibited. Do not navigate, fetch, scrape, crawl, scroll, or
execute DOM scripts against X. Do not use Grok as an indirect X collector and do not inspect
following graphs or profile metadata. When a user supplies an X URL, preserve it as
user-provided metadata without retrieving it; request the relevant text when needed and seek
a non-X primary source. See the current terms: <https://x.com/en/tos>.

## 3. Normalize and deduplicate

1. Normalize redirect/tracking variants to canonical URLs.
2. Group candidates by the underlying release, policy change, event, or announcement.
3. Prefer the primary source as the canonical item.
4. Attach corroborating sources to the canonical item.
5. Exclude items outside the requested window and retain an exclusion count.

## 4. Categorize and rank

Assign provider bucket and HIGH/MEDIUM/LOW tier using:

- practical availability and impact;
- relevance to the selected audience profile;
- novelty within the current window;
- source confidence and corroboration;
- whether a concrete release/change exists rather than a roadmap claim.

Never promote a secondary-only rumor to fact. Label secondary-only items and include them
only when their caveat is useful to the audience.

## 5. Emit markdown

Write run metadata, tiered provider sections, source links, dates, impact notes, and a
visible caveats section. Every factual item requires a source URL. Empty requested provider
buckets are explicit rather than silently omitted.

Machine-local artifacts and state go under `${CLAUDE_PLUGIN_DATA}/<profile>/`. Tracked
source, audience, and brand configuration remains in
`.claude/ai-briefing/[<profile>/]`.

## 6. Optional presentation build

Only after explicit `--format html` or `--format slides`:

1. Run the staged locked build tree from `${CLAUDE_PLUGIN_DATA}/runtime/build/`.
2. Pass the resolved profile explicitly to the build subprocess:

   ```bash
   AI_BRIEFING_PROFILE="$PROFILE" node "${CLAUDE_PLUGIN_DATA}/runtime/build/run.js"
   ```

3. Use Playwright only to open generated local HTML for PDF rendering, screenshots, and
   layout validation.
4. Do not use Playwright or another browser provider for source collection.
5. Fail visibly on missing dependencies, render errors, overflow, or invalid output.

## 7. Persist and report

Update the seen-item registry only after successful markdown emission. Report:

- collected, excluded, and deduplicated counts;
- primary-backed and secondary-only counts;
- inaccessible sources and partial provider coverage;
- output paths and optional render validation status.

Re-running the same window is idempotent: merge by canonical event identity and do not emit
duplicate items.
