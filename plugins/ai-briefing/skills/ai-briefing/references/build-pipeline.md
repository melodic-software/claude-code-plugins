# Build Pipeline — In-Tree Reference

Canonical pipeline for `--format slides|html` reproducing the deck (brand tokens in `output/build/brand.js`). Lives at `output/build/` under the skill.

This file documents the working pipeline schema + commands. For brand spec / slide order / split rules / provider logos, see `slide-generation.md`. For provider buckets / query templates, see `providers.md`.

## Pipeline files

| File | Role | Output |
|---|---|---|
| `run.js` | **Orchestrator** — chains emit → build (pptx+html+pdf) → validate. Single entrypoint | drives the chain |
| `emit-slides-data.js` | **Emitter** — reads briefing markdown + state, writes `slides-data.js`. Holiday-aware flair. Pre-flight provider-logo fetch. Zod schema validates before writing | `slides-data.js` |
| `slides-data.js` | **Generated** — slide content per current meeting. Do NOT hand-edit; re-run emitter. | data module consumed by build-* scripts |
| `lib/parse-briefing.js` | Markdown AST parser (remark + remark-gfm) — H2 buckets → H3 tiers → bullet items | — |
| `lib/emit-slides.js` | Items → slide objects (canonical order, HIGH≤5 split, MED≤14 split, cross-provider clusters, patterns synthesis) | — |
| `lib/holidays.js` | Run-date → holiday theme (US federal via date-holidays + tech custom map) | — |
| `lib/schema.js` | Zod discriminated union — 11 slide types, meta, theme, providerLogos | — |
| `lib/fetch-logos.js` | Auto-fetch missing simpleicons SVGs to `assets/`. 404s downgrade to null | populates `assets/logo-<slug>.svg` |
| `build-pptx.js` | pptxgenjs ESM — provider-aware decorate(), 11 slide types | `../meetings/ai-meeting-{N}.pptx` |
| `build-html.js` | Single-file HTML emitter — inline base64 org logos + inline SVG provider logos via `currentColor`; keyboard nav, prev/next buttons, touch swipe, hash deep-link, `?print=1` flag | `../meetings/ai-meeting-{N}.html` |
| `build-pdf.js` | Playwright headless chromium prints `?print=1` HTML to Letter landscape, 0-margin, one slide per page | `../meetings/ai-meeting-{N}.pdf` |
| `validate.js` | 6-gate validator — Zod schema, URL/headline coverage, console errors, content-slide overflow, linkinator URL reach, PDF text coverage (unpdf), PPTX slide count match (node-pptx-parser). Screenshots all slides | `build/shots/*.png` + `build/shots/audit.json` |
| `assets/` | Cached org logos (PNG) + provider logos (SVG from simpleicons CDN) | — |
| `package.json` | `playwright` + `pptxgenjs` + `remark-parse` + `remark-gfm` + `unified` + `unist-util-visit` + `zod` + `date-holidays` + `linkinator` + `unpdf` + `node-pptx-parser` | — |

## Prerequisites — one-time setup

```bash
cd output/build

npm install                                       # pptxgenjs ^4.0.1 + playwright ^1.59.1
npx playwright install chromium --only-shell      # ~120 MB, headless-only
```

Node 20+ required (ESM imports + top-level await). On Windows / Git Bash, use `pwsh` for npx if `npx.cmd` resolution flakes.

**Plugin form.** The plugin cache is read-only, so dependencies and every generated artifact live under `${CLAUDE_PLUGIN_DATA}` (keyed per profile), not beside the scripts. Run `/ai-briefing:setup` once to persist the build deps there, then invoke the build scripts from the plugin root with `NODE_PATH` pointed at the persisted modules: `NODE_PATH="${CLAUDE_PLUGIN_DATA}/deps/build/node_modules" node "${CLAUDE_PLUGIN_ROOT}/skills/ai-briefing/output/build/run.js"`. Emitted `slides-data.js`, decks, and screenshots land under `${CLAUDE_PLUGIN_DATA}/<profile>/output/`.

## Per-meeting build sequence

**Single entrypoint** (full chain — emit → build → validate):

```bash
cd output/build
node run.js
```

**Granular** (when overseer wants to inspect/edit between stages):

```bash
node emit-slides-data.js                    # Step 1 — emit slides-data.js from briefing.md
# AI overseer reviews slides-data.js: tier assignments, headline phrasing, flair candidates,
# patterns synthesis, cluster placement. Edit slides-data.js directly OR re-run emit with overrides.

node build-pptx.js                          # Step 2a — pptx
node build-html.js                          # Step 2b — html
node build-pdf.js                           # Step 2c — pdf

node validate.js                            # Step 3 — quality gates (Zod, URLs, overflow, links, PDF, PPTX)
# AI overseer reviews build/shots/slide-*.png + build/shots/audit.json before ship.
```

**Skip-emit** (rebuild from edited slides-data.js):

```bash
node run.js --skip-emit
```

**Emitter overrides** (passed through `run.js` too):

```bash
node emit-slides-data.js --meeting-n 21 --briefing ../meetings/meeting-21.md --date 2026-05-22
```

`validate.js` exits non-zero on **blocking** issues only (schema violation, URL coverage gap, console errors, content-slide overflow). Warnings (broken external links, PDF URL coverage gap, PPTX slide-count drift) print but do not block. **Treat warnings as overseer-review items** — AI looks at the audit, decides whether to ship or iterate.

## AI-in-loop checkpoints

Scripts make pipeline **efficient**, not autonomous. Overseer (Claude or human) holds judgment at these gates:

| Gate | Script does | Overseer does |
|---|---|---|
| **Briefing → slides-data emit** | Parses markdown, partitions tiers, splits HIGH/MED, places clusters, fetches logos, validates schema | Reviews emitted `slides-data.js`: are tier assignments right? Are headline truncations preserving meaning? Should any item be promoted/demoted? Edit and re-run |
| **Flair candidates** | Picks holiday theme from run-date; emits placeholder `flair` slide with curate-your-own slot | Reviews `holiday.searchHooks`, runs Perplexity/WebSearch for candidates, vets each for apolitical filter (drop politician deepfakes, keep brand parodies/science weirdness), edits `slides-data.js` `FLAIR.items[]` |
| **Patterns synthesis** | Emits stub `patterns` slide based on bucket presence | Reviews stub, replaces with curated cross-bucket themes the briefing actually surfaces — not a generic stub |
| **Apolitical filter** | Doesn't filter — passes everything through | Drops partisan-only items at briefing-emit time AND re-validates at slides-emit (defense in depth) |
| **Cross-provider clusters** | Routes "Legal", "Compute", "Real-world" H2 sections to dedicated slides | Decides if a sub-bullet inside another bucket should be promoted to a cluster slide (e.g., a Microsoft item that's actually a Musk-v-Altman co-defendant detail) |
| **Visual review** | Screenshots all 43 slides to `shots/slide-NN.png`, dumps `audit.json` | Reads screenshots, checks: text legibility, contrast, headline truncation natural, URL list density acceptable, no broken layouts, brand consistency |
| **Ship gate** | Prints "VALIDATION PASSED" on 0 blocking | Final go/no-go after visual + audit review. Iterate (edit briefing.md OR slides-data.js, re-run) until satisfied |

**Rule of thumb:** if a decision could embarrass the team in front of attendees (wrong tier, awkward headline, partisan flair, broken pattern claim), it's an overseer call. Scripts only handle decisions that have one mechanically-correct answer.

## `slides-data.js` schema

```js
export const meta = {
  meetingNumber: 20,
  org: "AI Briefing",
  tagline: "AI industry news, aggregated and ranked.",
  date: "2026-05-08",
  window: "2026-04-24 to 2026-05-05 (~11 days)",
  logoColor: "",
  logoWhite: "",
};

export const theme = {
  bg: "0F1424", bgAccent: "1C2440", bgCard: "2B3358",
  brandIndigo: "23305C", brandRed: "C0432E",
  accent: "6E8BFF", accent2: "F2B441", accent3: "8FB6FF",
  text: "FFFFFF", textMuted: "B4BAD4", divider: "3C456E",
  pptFontHead: "Arial", pptFontBody: "Arial",
  htmlFontHead: "'Segoe UI', system-ui, sans-serif",
  htmlFontBody: "'Open Sans', 'Segoe UI', system-ui, sans-serif",
};

export const providerLogos = {
  anthropic: "assets/logo-anthropic.svg",
  openai: "assets/logo-openai.svg",
  // ... see slide-generation.md "Provider logo registry" for full list
  deepseek: null,    // no upstream logo — text-only header
};

export const slides = [
  /* slide objects in canonical order — see Slide types below */
];
```

`meta` and `theme` are the default brand, sourced from `output/build/brand.js` — DO NOT redefine per run. Edit `brand.js` only on rebrand. `meta.meetingNumber`, `meta.date`, `meta.window` are the only `meta` fields that change per meeting.

## Slide types (11 total)

Each slide object has `type:` discriminating which renderer applies in `build-pptx.js` and `build-html.js`.

| `type` | Required fields | Optional | Renders |
|---|---|---|---|
| `title` | `eyebrow`, `title`, `subtitle`, `footer` | — | Hero title slide with org logo, brand-red top + gold bottom strips, glow ellipses, tagline |
| `agenda` | `title`, `items[]` | — | Numbered agenda cards (9-item meeting roadmap) |
| `section` | `title`, `lead`, `items[]` | — | Welcome & Goals — quote + pill row |
| `levels` | `title`, `levels[{n,label}]` | — | AI Generative Levels 0-5 reference |
| `open` | `title`, `subtitle` | `note` | Open share — kicks off news block |
| `news` | `title`, `bullets[{title,body,urls[]}]` | `subtitle`, `provider`, `tier` | HIGH-tier news slide; provider logo when `provider:` set |
| `condensed` | `title`, `bullets[{title,body,urls[]}]` | `subtitle`, `provider`, `tier` | MED/LOW condensed; auto-2-col when >7 bullets |
| `patterns` | `title`, `subtitle`, `items[{title,body}]` | — | Synthesis slide — cross-bucket themes |
| `prompt` | `title`, `prompt`, `note` | — | Discussion prompt (Tools / Tips / Problems) |
| `blank` | `title`, `placeholder` | — | Task Force Update placeholder |
| `qa` | `title`, `subtitle` | — | Q & A closing |
| `flair` | `title`, `subtitle`, `items[{title,body,urls[]}]` | — | Holiday-themed / viral AI / curate-your-own slot — always include |

### `tier` values for `news`/`condensed`

| `tier` | Eyebrow text | When |
|---|---|---|
| `"high"` | `"AI LATEST NEWS"` (no suffix) | top-impact items: model releases, major launches, industry-defining legal events |
| `"med"` | `"AI LATEST NEWS · medium signal"` | features, API changes, ecosystem moves |
| `"low"` | `"AI LATEST NEWS · low signal"` | color, criticism, minor updates |

### `provider` values

Slug from `providerLogos` map. Set `provider: null` for cross-provider clusters (Legal, Compute when no single chip dominates, Patterns synthesis, etc.).

## Per-meeting emit logic (slides-data.js generation)

When `--format slides|html` runs:

1. Read briefing source `output/meetings/meeting-{N}.md`
2. Read state `context/seen-items.json` for `meeting_n` (or use `--meeting-n` override)
3. Parse markdown → bucket each item by provider (13-bucket schema per SKILL.md / providers.md)
4. Within each bucket, partition by HIGH / MED / LOW
5. **Apolitical filter** — drop partisan-only items (already done at briefing-emit time per SKILL.md, but re-validate at slides-emit)
6. Emit slide objects in canonical order (see `slide-generation.md` "Canonical slide order")
   - HIGH bucket → `news` slide(s) — split when >7 bullets
   - MED bucket → `condensed` slide — auto 2-col when >7 bullets
   - LOW bucket → `condensed` slide — single-col
   - Cross-provider clusters → dedicated `news` slide (Legal/Compute/Real-world)
   - Patterns synthesis → `patterns` slide when ≥3 cross-bucket themes
   - Flair → `flair` slide always (placeholder if no items)
7. Resolve provider logos: for each unique `provider:` slug, ensure `assets/logo-<slug>.svg` exists; fetch missing via simpleicons CDN
8. Write `slides-data.js` (overwriting prior meeting's data)
9. Run pipeline: `build-pptx.js → build-html.js → build-pdf.js → validate.js`
10. On validate.js exit 0: increment `meeting_n` in `seen-items.json`, archive briefing

## HTML deck features

`build-html.js` emits a single self-contained file. No external dependencies at runtime (Google Fonts CDN is the one external — gracefully falls back to system fonts if offline).

### Navigation

- Keyboard: `←` / `→` / `Space` / `PgUp` / `PgDn` / `Home` / `End`
- Buttons: explicit prev/next in bottom-corners (visible)
- **NO click-to-advance** — clicks on URL links must not advance the deck (traps misclicks). Click event handler exits early when `event.target.closest("a")`.
- Touch: swipe left/right
- Deep-link: `#slide-N` jumps to slide N on page load

### Print mode

`?print=1` query param disables transitions, shows all slides simultaneously stacked for paged-media rendering. `build-pdf.js` uses this URL form.

### Responsive

Designed for 1600×900 viewport (validate.js uses this). Smaller viewports scale via CSS clamp() — readable down to 1024×768.

## PDF output

`build-pdf.js` parameters (Letter landscape):

```js
await page.pdf({
  format: "Letter",
  landscape: true,
  printBackground: true,
  margin: { top: 0, right: 0, bottom: 0, left: 0 },
  preferCSSPageSize: false,
});
```

One slide per page. Embeds fonts via Google Fonts CDN (Playwright-headless waits for `document.fonts.ready`).

## validate.js gates

| Check | Failure mode |
|---|---|
| All `slides-data.js` `bullets[].urls[]` render as `.news-url` anchors in DOM | Reports per-slide missing URLs; do not ship deck until 0 missing |
| Headline coverage: every `bullets[].title` text appears in `.news-headline` / `.condensed-headline` / `.flair-headline` | Reports per-slide missing headlines |
| Console errors: pageerror + console.error captured | Reports any console error — investigate before shipping |
| Slide-overflow: `slide.scrollHeight > slide.clientHeight + 4` | Flags slides where content exceeds viewport — split per slide-generation.md "Split rules" |
| List-overflow: `.news-list.scrollHeight > .news-list.clientHeight + 4` | Same — bullet count too high |

Outputs:

- `build/shots/slide-NN.png` — per-slide screenshot for visual review
- `build/shots/audit.json` — structured audit (counts, mismatches, overflow)

## Drift / recheck triggers

| Trigger | Action |
|---|---|
| pptxgenjs major version bump | Verify `addImage` data URI handling, `ShapeType.rect` / `ellipse` API |
| playwright major version bump | Re-test `chromium.launch` headless; `page.pdf` margin handling |
| simpleicons CDN URL changes | Update fetch script in `slide-generation.md` "Provider logo registry" |
| New provider added (slug missing) | Append to `providerLogos` map; fetch SVG to `assets/`; update `slide-generation.md` slug list |
| Org rebrands | Update `output/build/brand.js` `theme` + `brand` exports; update `slide-generation.md` "Default brand spec" |
| Node 20 EOL (April 2026) | Verify ESM + top-level await on Node 22+ |

---

## Slide/HTML/PDF generation (Step 5 detail)

When SKILL.md Step 5 hits `--format slides|html`, the canonical path runs through this in-tree pipeline (Node ESM, pptxgenjs + playwright direct). The fallback skill paths are documented in `slide-generation.md`.

### PPTX slides (`--format slides`)

**Canonical pipeline:** in-tree `output/build/*.js`. Reproduces the deck deterministically from the active brand (brand tokens in `output/build/brand.js`).

**Overseer-driven flow** (Claude is the overseer — runs scripts, reviews outputs, iterates):

```bash
cd output/build

# 1. Emit slides-data.js from briefing markdown (mechanical)
node emit-slides-data.js --meeting-n {N} --briefing ../meetings/meeting-{N}.md --date YYYY-MM-DD

# 2. AI REVIEW — read slides-data.js
#    - tier assignments (HIGH vs MED vs LOW reasonable?)
#    - headline truncations preserve meaning?
#    - Patterns synthesis stub (replace with curated cross-bucket themes from briefing)
#    Edit slides-data.js directly OR re-run emitter with overrides.

# 3. Build all 3 artifacts (mechanical)
node build-pptx.js && node build-html.js && node build-pdf.js

# 4. Validate (mechanical 6-gate audit)
node validate.js

# 5. AI REVIEW — read build/shots/slide-NN.png screenshots + build/shots/audit.json
#    - text legibility / contrast / spacing
#    - headline truncations natural?
#    - broken-link warnings actionable?
#    - overflow on content slides?

# 6. Ship gate — go/no-go
#    Iterate until satisfied (edit briefing.md OR slides-data.js, repeat from step 1 or 3)
```

`node run.js` chains steps 1+3+4 in one shot when no pause needed. Use granular form when an overseer judgment call is pending.

Default brand tokens (colors, fonts, logo paths) live in `output/build/brand.js` and are imported by `emit-slides-data.js` — do NOT redefine per run.

**Fallback path** (`/document-skills:pptx` skill): only when in-tree pipeline cannot run (Node missing, etc.). See `slide-generation.md` "Fallback skill paths" for skill-stack delegation. Default = in-tree.

### Slide structure (mirrors user's Canva deck)

1. Title slide (Engineering AI Meeting #N, Date)
2. AI Meeting Agenda
3. Welcome / Goals
4. AI Generative Levels (reference slide)
5. AI Latest News — one slide per provider with bullet points
6. AI Tools / Discussions
7. AI Tips & Tricks / Show N Tell
8. AI Problems?
9. AI Task Force Update
10. Feedback / Review Q&A

If `document-skills:pptx` is not available, follow the install steps in `slide-generation.md` "PPTX fallback".

### HTML slides (`--format html`)

**Canonical pipeline:** `output/build/build-html.js` produces single-file HTML with inline CSS/JS, base64 org logos, inline SVG provider logos (white via `currentColor`), keyboard nav (←/→/space/PgUp/PgDn/Home/End), explicit prev/next buttons (NO click-to-advance — traps misclicks on URL links), touch swipe, hash deep-link, `?print=1` flag for print mode.

**Summary:** Collect items → emit/update `output/build/slides-data.js` → run `node build-html.js` → output lands at `output/meetings/ai-meeting-{N}.html`. See "slide-data schema" earlier in this file for the schema and full type list.

**Fallback path** (`/frontend-design:frontend-design` + `/ui-ux-pro-max:slides`): see `slide-generation.md` "Fallback skill paths".

### PDF (post-generation)

**Canonical pipeline:** `output/build/build-pdf.js` — Playwright headless chromium prints `?print=1` HTML to Letter landscape, 0-margin, one slide per page. Run after `build-html.js`.

**Fallback paths** (when in-tree unavailable): see `slide-generation.md` "PDF fallback paths".
