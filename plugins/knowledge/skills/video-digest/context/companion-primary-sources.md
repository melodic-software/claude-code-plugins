# YouTube watch — companion primary sources

When an operator queues a video with a companion URL (blog post, doc, paper), the companion is **Tier 1/2 primary framing**; the video is Tier 2/3. Full protocol — cite by heading; do not duplicate bodies into `SKILL.md`.

## Queue-time recording

On `queue <url>` when the operator supplies companion URL(s) and intent:

1. Preflight the YouTube URL per `context/watch-queue.md`.
2. Derive `video-slug` early from preflight `title` + `videoId` (`derive-video-slug.js`).
3. `mkdir -p .work/<watch-epic>/<video-slug>/source`
4. Copy `templates/companion-source-brief.md` → `source/companion-sources.md`; fill URL(s), rationale, section fan-out table, integration checklist.
5. Append `QUEUE.md` row with `slug` pre-filled and `notes` pointing at `source/companion-sources.md`.

Dedupe by `video-id` unchanged. Companion brief may exist before any `run-watch.js` bootstrap.

## Phase 0b — Companion deep-dive (watch / resume)

**Gate:** When `source/companion-sources.md` exists, run Phase 0b **before** `run-watch.js` (or before vision on resume if CLI phases already complete but companion phase is not marked).

**Order:** Prerequisites (Phase 0) → **Companion (Phase 0b)** → CLI bootstrap (Phase 1) → vision/research/synthesis.

### Execution

1. Read `source/companion-sources.md` — section table is the fan-out SSOT.
2. WebFetch each companion URL (full page, not surface skim).
3. **Divide and conquer:** one subagent per major H2 section in the brief's fan-out table. Dense H2s (`Types of skills`, `Tips for making skills`) may sub-fan-out per `###` when the brief says so.
4. Each subagent runs deep external research on `<section-topic>` (single-vendor topics can use a lighter research pass) — no surface-level reads.
5. Write `source/companion-digest/<section-slug>.md` per section (claims, examples, gotchas, repo-relevant hooks).
6. Write hub `source/companion-digest/README.md` — links all section shards + one-paragraph synthesis.
7. Seed `source/harvested-links.json` with companion URL(s) typed `doc`, `priority: pre-watch` (create file if bootstrap has not run yet).
8. `mark-phase <slice-dir> companion` only after every section row in the brief has a digest shard.

### Resume

If `watch.json` exists with CLI phases done but `companion` not marked, run Phase 0b before vision. If companion is marked but digest shards are missing, re-run Phase 0b.

## Integration (downstream phases)

| Phase | How companion frames the work |
| --- | --- |
| Claim inventory | Tag video claims with `blog-ref: <section-slug>` where applicable; blog digest = baseline |
| Research agenda | Blog digest clusters = `done` baseline; video-only deltas get a research fan-out |
| Vision plan | Expect slides mirroring blog taxonomy; promote frames that **extend** blog, not duplicate (`synthesis-contract.md`) |
| Research | Video claims cross-check blog; blog URL in `research/sources.md` as primary citation |
| Synthesis | Menu items cite blog section + video timestamp when both apply |

Trust tiers: apply your project's own source-trust conventions. Repo conventions override both video and blog — surface conflicts explicitly.

## Blocking criteria

When `source/companion-sources.md` exists:

| Criterion | FAIL → |
| --- | --- |
| `source/companion-digest/README.md` exists | Phase 0b — write hub after section fan-out |
| Every section slug in brief has `source/companion-digest/<slug>.md` | Phase 0b — complete subagent fan-out |
| `mark-phase companion` in `watch.json` | Only after digest complete; before Phase 1 if starting fresh |

See `context/quality-gates.md` phase gates table.
