# Slide Generation — PPTX, HTML, PDF

This file documents how to generate presentation slides from ai-briefing output.

**Canonical pipeline = in-tree `output/build/*.js`** (Node ESM, pptxgenjs + playwright direct). Reproduces the deck deterministically from the active brand (default neutral tokens in `output/build/brand.js`, or a profile overlay). See `references/build-pipeline.md` for build commands, `slides-data.js` schema, slide types, and prerequisites.

The `/document-skills:pptx` skill stack is documented as a **fallback path** at the bottom of this file — only used when the in-tree pipeline cannot run.

## Default brand spec

These tokens are defined in `output/build/brand.js` (the neutral engine default) and embedded into the generated `slides-data.js` `theme` + `meta` exports by the emitter. Do NOT redefine per run; a consumer profile overlays `brand.js` to rebrand.

### Color palette (default)

| Token | Hex | Use |
|---|---|---|
| `bg` | `#0F1424` | deep navy background |
| `bgAccent` | `#1C2440` | secondary fills |
| `bgCard` | `#2B3358` | card / glow |
| `brandIndigo` | `#23305C` | brand deep indigo |
| `brandRed` | `#C0432E` | accent red — top accent strip |
| `accent` | `#6E8BFF` | periwinkle |
| `accent2` | `#F2B441` | gold — side rail, eyebrow text |
| `accent3` | `#8FB6FF` | sky |
| `text` | `#FFFFFF` | primary text |
| `textMuted` | `#B4BAD4` | secondary text |
| `divider` | `#3C456E` | dividers |

### Fonts (default)

- Heads / body: **Arial** in PPTX; system-font stacks in HTML (`'Segoe UI', system-ui, sans-serif` / `'Open Sans', 'Segoe UI', system-ui, sans-serif`). The defaults use only system fonts, so the HTML deck makes **no** remote webfont fetch out of the box. A profile that overlays a CDN webfont takes on that remote fetch (and any local no-remote-fetch policy) itself.

### Logos

The neutral default ships **no** org logo (`brand.js` `logoColor` / `logoWhite` are empty), and the build scripts skip logo embedding when empty. A profile supplies its own logo asset paths (base64-inlined in the HTML deck; embedded via pptxgenjs `addImage` in PPTX). Provider logos (Anthropic, OpenAI, …) ship bundled in `output/build/assets/` and are used nominatively per news item.

### Title slide elements

- Eyebrow: `<org>` (from `brand.js`; default `"AI Briefing"`)
- Title: `"AI Meeting #${meta.meetingNumber}"`
- Subtitle: meeting date
- Tagline: `meta.tagline` (default `"AI industry news, aggregated and ranked."`)
- Footer: `"Briefing window: ${meta.window}"` (e.g., "2026-04-24 to 2026-05-05 (~11 days)")

### Content-slide chrome

- Top: 0.1in brand-red strip across full width
- Left: 0.18in gold side rail (full height minus top strip)
- Top-right: org white logo (1.3in × 0.36in)
- Eyebrow text: small uppercase letter-spaced ("AI LATEST NEWS", "REFERENCE", "WELCOME", "MEETING ROADMAP", "SYNTHESIS", etc.) in periwinkle (`accent`)
- Footer: rendered from the `footerTemplate` in `output/build/brand.js` (e.g. `"<org> · AI Meeting #N · {date}"`) muted left + `"N / total"` muted right

## Provider logo registry

Logos cached at `output/build/assets/logo-<slug>.svg`, downloaded once from simpleicons CDN. HTML build inlines SVG with `fill: currentColor` so they render white-on-dark. PPTX build SHOULD use PNG variants (pptxgenjs cannot inline SVG with currentColor) — convert SVG → PNG via Inkscape or skip provider logo on PPTX side.

**CDN URL pattern:**

```
https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/<slug>.svg
```

**Required slug list** (download missing on first run):

| Provider key | simpleicons slug | Notes |
|---|---|---|
| anthropic | `anthropic` | |
| openai | `openai` | |
| google | `google` | |
| cursor | `cursor` | |
| microsoft | `microsoft` | |
| xai | `x` | xAI uses X logo (corporate) |
| meta | `meta` | |
| deepseek | — | no upstream slug; render text-only header |
| nvidia | `nvidia` | Compute & Infrastructure |
| tesla | `tesla` | Real-world AI |
| bun | `bun` | |
| langchain | `langchain` | |
| vscode | `visualstudiocode` | Other / Microsoft cross-listed |
| huggingface | `huggingface` | |
| firecrawl | `firecrawl` | add when first encountered |

**Add slugs as new providers appear** — append to `providerLogos` map in `slides-data.js`, fetch via curl/wget into `assets/`. Slides whose `provider:` key has no logo entry render text-only header (no error).

**Fetch script** (run when slug missing — never commit; assets/ is in repo):

```bash
SLUG=anthropic; curl -fsSL "https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/${SLUG}.svg" -o "output/build/assets/logo-${SLUG}.svg"
```

## Canonical slide order

Total typical: 35-50 slides. Order is fixed; sections may be empty (skip the slide entirely if bucket has 0 items, except "always-include" section).

| # | Type | Content | Always include? |
|---|---|---|---|
| 1 | `title` | `<org>` · AI Meeting #N · date · tagline · window footer (org/tagline from `brand.js`) | YES |
| 2 | `agenda` | 9-item meeting roadmap | YES |
| 3 | `section` | Welcome & Goals + Tips/Workflows/Show-and-Tell pills | YES |
| 4 | `levels` | AI Generative Levels 0-5 reference | YES |
| 5 | `open` | "Open share — anyone bring something to share?" | YES — always before news block |
| 6+ | `news` / `condensed` | Per-bucket HIGH → MED → LOW (see below) | per-bucket |
| ... | `news` (Legal cluster) | "Legal — Musk v. Altman trial" / copyright suits | when window has legal news |
| ... | `news` (Compute) | NVIDIA / AMD / hyperscaler / datacenter | when window has compute news |
| ... | `news` (Real-world AI) | Tesla Robotaxi / Waymo / humanoid prod | when window has real-world news |
| ... | `news` / `condensed` (EXTRAS) | Robotics HIGH → MED → LOW | when extras enabled |
| ... | `flair` | Holiday-themed + viral AI + curate-your-own slot | YES — always (placeholder OK) |
| N-5 | `patterns` | "Notable patterns this window" — synthesis | YES when ≥3 cross-bucket themes |
| N-4 | `prompt` | "AI Tools & Techniques" prompt + note | YES |
| N-3 | `prompt` | "AI Tips & Tricks · Show and Tell" prompt + note | YES |
| N-2 | `prompt` | "AI Problems" prompt + note | YES |
| N-1 | `blank` | "AI Task Force Update" placeholder | YES |
| N | `qa` | Q & A · Feedback · Review · Open Floor | YES |

### Per-bucket slide ordering (within news block)

For each bucket with items: HIGH first, then MED condensed, then LOW condensed. Buckets in this fixed order:

1. Anthropic
2. OpenAI
3. **Legal cluster** (cross-provider — slot here when industry-legal news present)
4. Google
5. Cursor
6. xAI / Grok
7. Meta / Llama
8. DeepSeek
9. Microsoft
10. Other (dev tools — Bun / VS Code / LangChain / Devin / etc.)
11. Compute & Infrastructure
12. Real-world AI
13. EXTRAS — Robotics HIGH + MED + LOW
14. Flair (always-include placeholder slot)
15. Patterns synthesis (when ≥3 themes)

### Split rules

- **HIGH news slides:** keep to **5-7 bullets max**. Overflow → split into "Provider — topic 1" + "Provider — topic 2" titled slides (see Anthropic Models & research / Reach & ecosystem in ai-meeting-20).
- **MED condensed:** **>7 items → 2-col layout** (`condensed-grid` CSS). 8-12 typical.
- **LOW condensed:** typically <5 items, single-col.

### Tier annotation

**Subtle eyebrow only.** No big "MED" / "LOW" badge in the slide corner.

- HIGH: eyebrow = `"AI LATEST NEWS"` (no suffix)
- MED: eyebrow = `"AI LATEST NEWS · medium signal"`
- LOW: eyebrow = `"AI LATEST NEWS · low signal"`

Eyebrow text is small uppercase periwinkle — presenter sees the tier, audience focus stays on content.

### URL rendering rule

**EVERY bullet renders ALL its source URLs** — never drop URLs after the first. Source markdown's `" · "` separator splits multiple URLs; render each as a clickable line under the bullet body.

`validate.js` enforces this at gate time — every URL in `slides-data.js` `bullets[].urls[]` must appear in DOM as `.news-url` anchor.

### Cross-provider clusters

| Slide | Provider key for logo | When include |
|---|---|---|
| **Legal — `<case>`** | `null` (no logo — cross-provider) | major industry-legal news in window: Musk v. Altman, copyright suits, state AGs, FTC/DOJ, EU AI Act enforcement |
| **Compute & Infrastructure** | `nvidia` (when dominant) or `null` | chip launches, hyperscaler GPU deals, datacenter capacity |
| **Real-world AI — autonomous vehicles** | `tesla` (when dominant) or `null` | robotaxi launches, fleet expansions, humanoid production cadence |
| **Patterns synthesis** | `null` | always when ≥3 cross-bucket themes detected |
| **Flair** | `null` | always — even with curate-your-own placeholder |

### Apolitical filter — flair gate

Drop politician deepfakes, partisan campaign AI memes, partisan policy threads. KEEP brand parodies (PETA-style), fan-art trailers (Wes Anderson Star Wars), science weirdness (fly-brain emulation), real-world AI moments. Industry-controversy items go to **Legal cluster**, not Flair. See SKILL.md "Apolitical filter" for full heuristic.

## Meeting number auto-increment

Read `meeting_n` from `context/seen-items.json`. On `--format slides|html`:

1. Read current `meeting_n` (defaults to 0 if missing)
2. Increment by 1: `meeting_n += 1`
3. Use `meeting_n` for the title slide (`slides-data.js` `meta.meetingNumber`)
4. Write incremented value back to `seen-items.json` AFTER successful slide generation
5. If user passes `--meeting-n <N>` flag, override auto-increment with explicit number — do NOT increment state

`slides-data.js` is rewritten per run (briefing markdown → emit data file → run pipeline). The hardcoded `meetingNumber: 20` in the existing file is the LAST run's value — overwritten on next emit.

## In-tree build pipeline (canonical)

See `references/build-pipeline.md` for full schema, commands, and dependency setup. Quick summary:

```bash
cd output/build

# One-time setup
npm install                          # pptxgenjs + playwright
npx playwright install chromium --only-shell

# Per-meeting build
# (1) Emit slides-data.js from briefing markdown
# (2) Run the pipeline:
node build-pptx.js                   # → ../meetings/ai-meeting-{N}.pptx
node build-html.js                   # → ../meetings/ai-meeting-{N}.html
node build-pdf.js                    # → ../meetings/ai-meeting-{N}.pdf
node validate.js                     # gate: all URLs render, 0 console errors
```

`validate.js` is the **must-pass gate** — fails if any source URL in `slides-data.js` doesn't render in DOM, or if any console error fires.

## Fallback skill paths (when in-tree pipeline unavailable)

These paths are documented for completeness — the in-tree `output/build/*.js` pipeline is canonical and reproduces org branding deterministically. Use a fallback skill ONLY when the in-tree pipeline cannot run (Node unavailable or build pipeline broken). All three are graceful fallbacks, not the critical path.

### PPTX fallback

Invoke `/document-skills:pptx` (marketplace `anthropic-agent-skills`) for `--format slides` when in-tree `build-pptx.js` is unavailable. It does not auto-apply org brand — you must pass theme tokens explicitly. Result deviates from the canonical look unless brand tokens are reproduced verbatim from `slides-data.js` `theme`.

### HTML fallback

Invoke `/frontend-design:frontend-design` (marketplace `claude-plugins-official`) for `--format html` when in-tree `build-html.js` is unavailable, paired with `/ui-ux-pro-max:slides` (marketplace `claude-plugins-official`) for slide layout patterns. These do not include keyboard nav / `?print=1` flag / SVG provider logos out of the box — reproduce those from `build-html.js`.

### PDF fallback paths

- **HTML → PDF:** `npx playwright cli pdf <html> <pdf> --format=Letter --landscape --print-background` (replaces `build-pdf.js` if missing)
- **PPTX → PDF:** `soffice --headless --convert-to pdf <pptx>` (LibreOffice) or PowerPoint File→Export

### Skill stack reference (only relevant for fallback)

| Skill | Source | Role |
|---|---|---|
| `document-skills:pptx` | `anthropic-agent-skills` | PPTX fallback |
| `document-skills:pdf` | same | PDF post-processing (merge cover/body, extract verification) |
| `document-skills:theme-factory` | same | 10 preset themes (use only as starting point — re-apply org brand tokens after) |
| `frontend-design:frontend-design` | `claude-plugins-official` | HTML fallback |
| `ui-ux-pro-max:slides` | `ui-ux-pro-max-skill` | layout patterns / emotion arcs (Team All-Hands closest to AI-meeting structure) |
| `ui-ux-pro-max:ui-ux-pro-max` | same | 161 palettes, 57 font pairings (do NOT use — org brand is canonical) |

## Stale references — DO NOT use

These tools are NOT installed and superseded by the in-tree pipeline:

| Stale ref | Why removed |
|---|---|
| `tfriedel/claude-office-skills` | Third-party, unmaintained |
| `zarazhangrui/frontend-slides` | Third-party, single-author |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `validate.js` reports missing URLs | Source slides-data.js `urls[]` array not rendering — check escape + bullet template in `build-html.js` |
| Provider logo missing | Slug not in `providerLogos` map OR file not in `assets/` — fetch via simpleicons CDN |
| Slide overflow flagged by validate.js | HIGH slide has too many bullets — split into multiple slides per "Split rules" |
| PPTX font fallback wrong | Ubuntu / Cabin not installed locally — pptxgenjs falls back to default; HTML deck still renders correctly via Google Fonts CDN |
| LibreOffice `soffice` not found (fallback PDF path) | `winget install TheDocumentFoundation.LibreOffice` (Windows) |
| `/document-skills:pptx` not in slash menu (fallback) | `/reload-plugins`, then `/doctor` if still missing |
