# Plugin web reads and the shared docs cache

This inventory lists every web read the plugins under `plugins/` make outside the shared docs
cache, with a verdict for each. The cache is `lib/fetch-docs.sh --cache` over `lib/docs-cache.sh`,
vendored into a plugin as `scripts/fetch-docs.sh` and registered in `scripts/shared-copies.txt`
([ADR 0057](../adr/0057-share-a-user-scope-docs-cache-across-plugins.md)).

- **moved**: the read fetches a page by URL and belongs on the plugin's `fetch-docs.sh --cache`
  copy. The second part of #18298 makes these moves, adding a vendored copy where the plugin has
  none.
- **kept**: the read stays on WebFetch, curl or the language's HTTP client, for the reason in its
  row.

Plugins whose reads are all kept, and plugins with no web reads, take no code change and no
changelog fragment for this work. This file is the only place that lists them.

## Scope

Searched at commit `555ae87e`:

- Agent `tools:` lists and skill `allowed-tools:` that grant WebFetch.
- Skill, agent, workflow and reference text that tells a session to read a URL with WebFetch or
  `curl`.
- Scripts and hooks that call `curl`, `wget`, `Invoke-WebRequest`, Python's `urllib.request` or
  `http.client`, Node's `http` and `https` modules, JavaScript's `fetch`, or an API SDK client.

Not listed, because none of these is a web read outside the cache:

- Tests, evals, fixtures, mocks, READMEs and CHANGELOGs.
- The cache itself: every vendored `fetch-docs.sh`, `docs-cache.sh` and `docs-raw.sh`, and every
  read that already goes through them.
- Loopback and same-origin requests: the session bridges and `watch.sh` watchers in `planning`,
  `prototype`, `review` and `work-items`; every `lib/view-runtime.js`; browser-side page code in
  `animation`, `pixel-art`, `planning` and `prototype`; the OTel probes in `harness-ops`; and the
  app under test in `testing`'s `run-e2e`.
- Text that names a network tool without reading anything: permission lints, tool-name lists,
  guard hooks that match `curl` or WebFetch, discovery's WebFetch truncation hook, multi-agent's
  drift-checker fetch gate, recorded evidence such as `gaming`'s `anticheat-posture.md`, and lines
  that tell the reader not to use WebFetch.

## Reads

Each path is relative to `plugins/<plugin>/`, and line numbers are as of the commit above.

| Plugin | File:line | Read | Verdict | Why kept |
|---|---|---|---|---|
| ai-briefing | `skills/generate/SKILL.md:94` | WebFetch on the profile's news sources, item links and search results | kept | News feeds and release pages, not docs pages; each run reads them once for new items |
| attribution | `skills/audit/reference/source-fetch.md:65` | Summarizing fetch of a page | kept | Fallback for when the cached `.md` read fails; the primary read is already on the cache |
| autonomy | `skills/setup/context/pipeline-slots.md:52` | WebFetch on each vendor's pricing page | kept | Pricing pages are marketing pages read for the current price, shown with the fetch date, and the skill writes nothing to disk |
| context7 | `skills/lookup/scripts/update.sh:104` | curl of upstream `SKILL.md` files at a pinned SHA | kept | Drift check: compares exact upstream bytes against a baseline, so a copy another session cached is no evidence; a skill source file, not a docs page |
| context7 | `lib/cli-version-check.mjs:104` | fetch of the npm registry's latest-version JSON | kept | Registry API, not a page |
| discovery | `agents/research-verifier.md:4` | WebFetch grant | kept | Read-only verifier with no Bash; reads the parent's snapshot from disk and uses WebFetch only for a cited page the snapshot lacks |
| discovery | `agents/researcher.md:176` | curl download of artifacts too large to read in context | kept | Same as the `discipline.md:256` row: the artifact's bytes are kept as downloaded |
| discovery | `agents/sweep-worker.md:4` | WebFetch grant | kept | No shell by design; docs pages reach it as slices (page sections) that the docs-fetcher agent read through the cache |
| discovery | `workflows/research-sweep.js:235` | Workers WebFetch a page the slices do not cover | kept | The workers have no shell; every page the slices hold came through the cache |
| discovery | `skills/research/context/source-categories.md:12` | WebFetch the docs site when no docs MCP server is connected | moved | |
| discovery | `skills/research/context/discipline.md:68` | WebFetch on a raw `CHANGELOG.md` URL for the recency gate | moved | |
| discovery | `skills/research/context/discipline.md:256` | curl download of a PDF, spec or source file | kept | Not a page: the artifact's bytes are kept as downloaded, and the cache stores only markdown or converted HTML |
| discovery | `skills/research/context/discipline.md:312` | WebFetch when a synthesis tool is lost | kept | WebFetch only finds which page to read; the page is then read through the cache |
| dometrain | `skills/update/scripts/update.sh:72` | curl of the upstream `SKILL.md` | kept | Drift check against a baseline; a skill source file, not a docs page |
| education | `skills/teach/context/pedagogy.md:35` | WebFetch as the last fallback | kept | Fallback for when `/discovery:research`, which reads through the cache, is not enabled; the plugin carries no cache copy |
| event-storming | `skills/methodology/SKILL.md:95` | WebSearch and WebFetch for domain context | kept | Open research on search results, not docs pages; WebFetch's prompt pulls the domain facts |
| event-storming | `skills/simulation/reference/agentic-simulation.md:173` | WebSearch and WebFetch for domain context | kept | Same as the methodology row |
| external-agents | `scripts/lib/update.mjs:48` | fetch of the provider's config reference docs page | moved | |
| external-agents | `scripts/lib/update.mjs:61` | HEAD request to the provider's docs index | kept | Reachability probe; reads no body |
| external-agents | `lib/cli-version-check.mjs:104` | fetch of the npm registry's latest-version JSON | kept | Registry API, not a page |
| firecrawl | `skills/firecrawl/SKILL.md:78` | Prefer WebFetch for a simple page, the Firecrawl CLI otherwise | kept | Routing for any page, including pages that block plain HTTP clients or need JavaScript; the cache's curl read is blocked the same way |
| firecrawl | `skills/update/scripts/update.sh:94` | curl of the npm registry's latest-version JSON | kept | Registry API, not a page |
| firecrawl | `skills/update/scripts/update.sh:103` | curl of the upstream `SKILL.md` | kept | Drift check against a baseline; a skill source file, not a docs page |
| firecrawl | `lib/cli-version-check.mjs:104` | fetch of the npm registry's latest-version JSON | kept | Registry API, not a page |
| gaming | `skills/dlss5/reference/upstream-watch.md:56` | WebFetch on NVIDIA's GeForce news index | kept | News index read for new title names, not a docs page |
| gaming | `skills/dlss5/scripts/Invoke-Dlss5Mod.ps1:99` | `Invoke-WebRequest` for release metadata | kept | API call with request headers, not a page |
| gaming | `skills/dlss5/scripts/Invoke-Dlss5Mod.ps1:1119` | `Invoke-WebRequest` download of a pinned zip | kept | Binary download |
| gaming | `skills/dlss5/scripts/Invoke-Dlss5Mod.ps1:1186` | `Invoke-WebRequest` download of a release file | kept | Binary download |
| guardrails | `hooks/cloud-shfmt.sh:42` | curl download of the pinned `shfmt` binary | kept | Binary download checked against a SHA-256 |
| harness-config | `skills/audit/scripts/check-plugin-drift.sh:206` | curl of a marketplace's `marketplace.json` | kept | JSON manifest compared against installed state, so it must be fresh; not a page |
| harness-ops | `skills/audit-plugin-landscape/SKILL.md:89` | WebFetch when the discovery plugin is not enabled | moved | |
| harness-ops | `skills/changelog/SKILL.md:135` | Research subagents read a changelog entry or a GitHub issue with curl | moved | Only the changelog read moves; the GitHub issue read in the same sentence is kept, since an issue is not a docs page |
| harness-ops | `skills/known-issues/context/action-quality.md:11` | WebFetch or curl of Marginlab and status.claude.com | kept | The data sits in the pages' script objects, which the cache's HTML-to-markdown conversion drops |
| harness-ops | `skills/known-issues/context/action-search.md:37` | curl of status.claude.com | kept | Live status page, read fresh each time; not a docs page |
| harness-ops | `skills/known-issues/context/action-status.md:26` | curl of status.claude.com | kept | Live status page, read fresh each time; not a docs page |
| harness-ops | `skills/behavior-probes/cases/sandbox/network-blocked-outside-allowlist/prompt.md:1` | curl of example.com | kept | A probe that expects the sandbox to block the request |
| implementation | `agents/implementer.md:7` | WebFetch grant | kept | General worker grant for whatever page an item names; no fixed docs page |
| implementation | `agents/scoped-implementer.md:7` | WebFetch grant | kept | Same as the implementer row |
| kindle-dedrm | `skills/manage/reference/workflow.md:30` | curl downloads, also at lines 49 and 71 | kept | Binary downloads (installer and zips) |
| kindle-dedrm | `skills/manage/scripts/check-drift.sh:59` | curl HEAD request to pinned URLs | kept | Reachability probe; reads no body |
| knowledge | `agents/digest-worker.md:4` | WebFetch grant | kept | Rendered reads for presence claims only; absence reads already go through `fetch-docs.sh --cache --max-age 0` (`skills/docpage-digest/context/anthropic-docs-profile.md:116`) |
| knowledge | `skills/video-digest/context/watch-pipeline.md:139` | WebFetch previews of harvested links, also at line 320 | kept | Previews that rank arbitrary links by WebFetch's prompt; not docs reads |
| knowledge | `skills/course-digest/extraction/lib/players/hotmart.js:102` | fetch of subtitle segments, also at line 327 | kept | Runs inside the course player's frame for its session and CORS; not a page |
| knowledge | `skills/course-digest/extraction/download-resources.js:47` | `node:https` download of course resources | kept | File downloads such as PDFs, not pages |
| knowledge | `skills/video-digest/extraction/harvesting/fetch-deck-attachments.js:256` | `node:https` download of deck attachments from harvested links | kept | File downloads, not pages |
| knowledge | `skills/map-corpus/discovery/link-map-format.md:31` | WebFetch or curl of discovery snapshots | kept | Sitemaps and forge tree listings that a deterministic parser reads byte for byte; the pages themselves are read by the fetch route (line 35) |
| machine-health | `skills/audit/scripts/windows/lib/Invoke-AllowlistedWeb.ps1:92` | `Invoke-WebRequest` behind a host allowlist | kept | Microsoft Update, winget and CISA KEV data endpoints, logged per call; not docs pages |
| machine-health | `skills/audit/scripts/windows/lib/Get-CisaKevCache.ps1:141` | CISA KEV feed download | kept | JSON data feed with its own cache; not a page |
| miro | `server/src/miro-client.ts:33` | Miro REST API through the `@mirohq/miro-api` SDK | kept | Authenticated API, not a page |
| multi-agent | `agents/drift-checker.md:4` | WebFetch grant | kept | WebFetch-only judge by design, held to first-party docs hosts by a hook; pages reach it as slices read through the cache |
| multi-agent | `workflows/drift-audit.js:310` | Checkers WebFetch a page the slices do not cover, also at line 312 | kept | The checkers have no shell; every page the slices hold came through the cache |
| multi-agent | `skills/audit-defaults/SKILL.md:110` | WebFetch when the cached read fails | kept | Fallback for when the cached read fails |
| performance | `agents/go-faster-sweeper.md:4` | WebFetch grant | kept | Fallback for a pointer `fetch-docs.sh` records unread |
| performance | `skills/go-faster/reference/areas.md:53` | WebFetch when the manifest records a page unread | kept | Fallback; the primary read is already on the cache |
| planning | `skills/devils-advocate/SKILL.md:146` | WebSearch and WebFetch | kept | Open research on search results, not docs pages |
| planning | `skills/draft-goal-condition/SKILL.md:118` | WebFetch when the manifest records the page unread | kept | Fallback; the primary read is already on the cache |
| planning | `offers/offer-source.mjs:28` | fetch of the GitHub REST API | kept | Forge API, not a page |
| planning | `shared/cfdns.py:95` | Cloudflare DNS API | kept | Authenticated API call, not a page |
| planning | `shared/server.py:552` | HTTPS probe through the user's tunnel address | kept | Probes the user's own tunnel, not a page |
| planning | `shared/share.py:300` | HTTPS lease probe to the user's tunnel host | kept | Probes the user's own tunnel, not a page |
| playbooks | `skills/fable-5/SKILL.md:142` | WebFetch when the manifest records the page unread | kept | Fallback; the primary read is already on the cache |
| playbooks | `skills/boris/scripts/update.sh:77` | curl of the upstream version JSON | kept | API, not a page |
| playbooks | `skills/boris/scripts/update.sh:86` | curl of the upstream skill file | kept | Drift check that vendors the bytes verbatim; a skill source file, not a docs page |
| playbooks | `skills/boris/vendor/upstream-skill.md:45` | Upstream text telling a session to WebFetch a version URL | kept | Vendored third-party text treated as data; the skill never runs it (`skills/boris/scripts/update.sh:192`) |
| playbooks | `skills/skill-authoring/scripts/update.sh:76` | curl of the upstream skill file | kept | Drift check that vendors the bytes verbatim; a skill source file, not a docs page |
| playwright | `lib/cli-version-check.mjs:104` | fetch of the npm registry's latest-version JSON | kept | Registry API, not a page |
| plugin-quality | `agents/auditor.md:6` | WebFetch grant | kept | Fallback for when `fetch-docs.sh` records a page unread or writes no manifest |
| session-flow | `skills/workflow/context/continuation.md:225` | WebFetch on each pointer when the discovery plugin is not enabled | moved | |
| session-flow | `skills/retro/reference/ecosystem-improvement-catalog.md:14` | WebFetch when the manifest records the page unread | kept | Fallback; the primary read is already on the cache |
| songwriting | `skills/suno/SKILL.md:213` | WebFetch for BPM and key | kept | One-fact lookups that WebFetch's prompt pulls from encyclopedia and lyrics pages |
| songwriting | `skills/suno/context/research-recipes.md:25` | WebFetch on canonical sources, also at line 157 | kept | Same as the SKILL.md row |
| songwriting | `context/pat-pattison/scripts/datamuse.sh:48` | curl of the Datamuse API | kept | API, not a page |
| source-control | `skills/pull-request/reference/dependency-ci.md:18` | WebFetch on upstream changelogs and release notes | kept | The reviewer runs with no shell, so it cannot run `fetch-docs.sh` |
| source-control | `skills/babysit-prs/scripts/babysit_merge_policy.py:5732` | `urllib` read of the npm and PyPI registries | kept | Registry API, not a page |
| speech | `reference/elevenlabs.md:58` | curl download of the ElevenLabs OpenAPI spec | kept | A JSON spec too large for a page read, not a page |
| speech | `scripts/assets.py:76` | Model file download | kept | Binary download |
| speech | `scripts/elevenlabs.py:183` | ElevenLabs API | kept | Authenticated API call, not a page |
| speech | `scripts/narrate.py:429` | OpenAI speech API | kept | Authenticated API call, not a page |
| user-interface | `skills/write-css/SKILL.md:60` | WebFetch on official docs when context7 and discovery are absent | kept | Fallback for when `/context7:lookup` and `/discovery:research` are not enabled; the plugin carries no cache copy |
| user-interface | `skills/write-animation/SKILL.md:65` | WebFetch on official docs as the fourth route | kept | Used when `/context7:lookup` and `/discovery:research` give no answer; the plugin carries no cache copy |
| wizard | `skills/generate/template.sh:778` | curl in an example stage | kept | Example text the author deletes; an API call, not a page |
| work-items | `skills/onboard-adapter/scripts/templates/common.sh.tmpl:286` | Tracker REST call in the generated adapter template | kept | Authenticated tracker API, not a page |
| work-items | `tools/work-item-tracker/seeds/gitea/common.sh:321` | Gitea REST API | kept | Authenticated tracker API, not a page |
| work-items | `tools/work-item-tracker/seeds/jira/common.sh:297` | Jira REST API | kept | Authenticated tracker API, not a page |
| work-items | `tools/work-item-tracker/seeds/linear/common.sh:360` | Linear GraphQL API | kept | Authenticated tracker API, not a page |
| work-items | `tools/work-item-tracker/conformance/bindings/linear.sh:49` | Linear GraphQL API | kept | Authenticated tracker API, not a page |
| work-items | `tools/work-item-tracker/seeds/linear/schema-check/fetch-schema.sh:16` | curl of Linear's `schema.graphql` | kept | Schema file compared against the adapter, not a page |
| x | `skills/read/SKILL.md:6` | WebFetch grant for threadreaderapp.com, used at line 252 | kept | Fallback rendering of an X thread, presented as a summary; not a docs page |
| x | `skills/read/SKILL.md:154` | curl POST to the xtomd converter, also in `context/sources.md:61` to 75 | kept | POST-only converter endpoint; the cache fetches with GET |

## Plugins with moved reads

discovery, external-agents, harness-ops and session-flow. Each carries a `fetch-docs.sh` copy.

## Plugins with all reads kept

ai-briefing, attribution, autonomy, context7, dometrain, education, event-storming, firecrawl,
gaming, guardrails, harness-config, implementation, kindle-dedrm, knowledge, machine-health, miro,
multi-agent, performance, planning, playbooks, playwright, plugin-quality, songwriting,
source-control, speech, user-interface, wizard, work-items and x.

## Plugins with no web reads

actionlint, adhd, ai-slop, animation, app-control, architecture, bash-format, bugs, code-metrics,
code-tidying, codebase-health, computer-use, context-budget, context-usage, corrections, coupling,
debugging, desktop-notification, developer-experience, discipline, disk-hygiene,
display-redaction, docs-hygiene, docs-naming, domain-driven-design, eol-normalizer, evals,
explainer-video, fleet, formal-verification, github, go-format, harness-memory, improvement,
instruction-placement, javascript-format, markdown-format, mcp-tools, mutation-testing,
naming, overengineering, pixel-art, playgrounds, plugin-diagnostics, plugin-profiles,
powershell-format, prototype, python-format, rate-limits, repo-fleet-hygiene, repo-hygiene,
retro-audio, review, session-telemetry, skill-quality, spelling, sql-server, tdd, testing, themes,
toolchain, user-experience, verification, visualization and writing.

discipline, harness-memory and instruction-placement read docs pages, but only through their
`fetch-docs.sh --cache` copies, so they have nothing to move.
