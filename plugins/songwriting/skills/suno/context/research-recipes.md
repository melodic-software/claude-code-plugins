# Research recipes (the `/suno research` action)

The `research` action does **on-the-fly external lookups** to fill gaps static skill content can't cover: artist sonic profiles, current trends, genre nuances for niche styles, BPM/key for specific reference songs, recording / production technique deep-dives.

## When to invoke

Trigger `research` when the user's intent involves any of:

- **"Sound like <artist>"** — need that artist's sonic signature translated to Suno descriptors
- **"Mix of X, Y, Z"** with non-obvious genres (one-off subgenres, regional styles)
- **Reference a specific song** by title — need BPM, key, instrumentation, production characteristics
- **Current trend** ("2026 hyperpop", "what's TikTok hip-hop sounding like right now")
- **Niche genre** the static templates don't cover (zeuhl, witch house, slowcore, mariachi, gqom, drill regional variants)
- **Recording / mic / production technique** — gear-specific or technique-specific advice
- **Live event-driven** — Suno feature shipped this month, model update, current pricing tier change

## How the action runs

Research orchestrator. Run these phases in order; STOP early if Phase 1 returns enough.

### Phase 1: cheap lookup (Tier 1 sources)

Tools (in priority order):

1. **WebFetch** on canonical sources:
   - `help.suno.com` — for Suno feature questions
   - Wikipedia — for artist / genre / song basic facts (BPM, key, year, genre tags)
   - Genius / SecondHandSongs — for song lyrics + structural metadata
   - AllMusic — for genre lineage + influences
2. **Perplexity** (`mcp__perplexity__perplexity_search` or `perplexity_ask`) — for synthesis across recent sources, recency-filtered queries
3. **Context7** — only if user references a specific tool/SDK/library (rarely applicable for Suno prompting)

For artist sonic profile, the canonical query shape:

```
"Describe the sonic signature of <artist>: typical instrumentation,
production style, vocal characteristics, signature BPM range, key
preferences, mix philosophy, era/influences. Cite primary sources."
```

For current-trend research:

```
perplexity_search with recency_filter='month' or 'year':
"Current trends in <genre> production 2026 — instrumentation,
BPM ranges, vocal styles, common signature elements"
```

### Phase 2: synthesis into Suno descriptors

Translate findings into the 6-layer formula vocabulary:

| Research finding | Suno descriptor |
|------------------|-----------------|
| "Records to Pro Tools with vintage Neumann U67" | `vintage tube warmth, polished mix` |
| "Songs typically 92-98 BPM in F minor" | `95 BPM, F minor` |
| "Signature blues-rock fingerpicking on Strat" | `blues-rock fingerpicked Stratocaster, warm clean tone` |
| "Layered vocal harmonies, slight Auto-Tune" | `layered vocal harmonies, subtle pitch correction` |
| "Trap with mumble flow, dark moods" | `melodic trap, mumbling flow, dark and melancholic` |
| "Room sound, no compression, raw takes" | `intimate room mic, dry mix, no heavy compression` |

**Strip:**

- Artist names (filtered by Suno)
- Producer names (same)
- Album names (same)
- Song titles (same)
- Specific gear brand names that don't translate to public sound descriptors

### Phase 3: confidence-flagged output

Return:

1. **Style prompt block** — full 6-layer formula using research-derived descriptors
2. **Lyrics shell** — section structure matching the artist's typical song format if researched
3. **Confidence note** — HIGH if claims confirmed by primary sources, MEDIUM if Perplexity synthesis only, LOW if speculative
4. **Source citations** — URLs for the user to verify
5. **Suno-specific caveats** — any descriptor that's known to be ignored (e.g., naming the artist directly), workarounds applied

## Worked example: "I want a song to sound like John Mayer"

**Phase 1 lookup** (Wikipedia + AllMusic + Perplexity):

- Genre: blues rock, pop rock, soft rock, with strong blues guitar foundation
- Lead instrument: Stratocaster, fingerpicked, warm clean tone with light overdrive on solos
- Vocal: breathy male tenor, intimate phrasing, light vibrato, conversational delivery
- Tempo range: 75-105 BPM dominant; ballads slower
- Production: polished but organic, room sound preserved, layered acoustic-electric textures
- Era influences: SRV, Clapton, Hendrix on guitar side; Marvin Gaye on songwriting

**Phase 2 translation:**

```
blues-rock pop, warm and contemplative,
fingerpicked Stratocaster with light overdrive on leads,
warm acoustic guitar layered, upright bass, brushed drums,
breathy male tenor with intimate phrasing and light vibrato, 90 BPM,
key of A minor, polished but organic mix with room warmth,
no autotune, no electronic instruments
```

**Phase 3 output:**

- Confidence: HIGH on instrumentation + tempo (well-documented), MEDIUM on production "feel" (translates from descriptive language)
- Caveat: never name the artist in Suno — already stripped
- Sources: Wikipedia <artist-page>, AllMusic <bio-url>, Perplexity synthesis 2026

## Worked example: "Mix of dream pop, modern pop, synthesizer, modern retro throwback"

**Phase 1 lookup:**

- Dream pop: ethereal vocals, reverb-soaked, washy guitars, mid-tempo
- Modern pop: tight production, polished mix, vocal layering
- Synth-driven: analog or digital lead synths, pad layers
- Modern retro throwback: 80s synth-pop revival currently strong (Weeknd, Dua Lipa-era influences) — gated drums, FM bass, neon-colored chord progressions

**Phase 2 translation:**

```
dream-pop synth-pop fusion, 80s-inspired with modern polish,
nostalgic and euphoric, shimmering reverb-soaked guitar,
warm analog Moog bass, gated drum machine, lush layered synth pads,
ethereal female vocals with reverb tail and subtle layered harmonies, 110 BPM,
modern hi-fi production with vintage analog warmth, no autotune
```

**Phase 3 output:**

- Confidence: HIGH (combines well-documented genre conventions)
- Caveat: hybrid genre tag stack at 2 max (`dream-pop synth-pop`) to avoid the 3+ stacked genres anti-pattern
- Tweak knobs: swap `gated drum machine` → `live drums` for more organic; raise BPM for energy

## When research finds nothing useful

If Phase 1 + Phase 2 return nothing actionable (rare — genre's too obscure or artist's catalog too small):

1. Tell the user honestly — don't fake it
2. Ask 2-3 clarifying questions to anchor the prompt manually:
   - "Pick 1-2 reference songs you like — I'll use those as proxy"
   - "Era + region? (90s UK, 2020s LA, etc.)"
   - "Energy level? (chill / mid / hype)"
   - "Vocal style? (clean / raw / melismatic / spoken)"
3. Build from those answers using standard 6-layer formula

## Tools available

| Tool | Use for |
|------|---------|
| WebFetch | help.suno.com pages, Wikipedia, AllMusic, Genius — direct URL fetches |
| `mcp__perplexity__perplexity_search` | Web search with citations |
| `mcp__perplexity__perplexity_ask` | Quick Q&A with grounded synthesis |
| `mcp__perplexity__perplexity_research` | Slow deep-research mode (only for genuinely complex queries) |
| `mcp__ref__ref_search_documentation` | Documentation search if Suno-internal |
| Firecrawl | Fallback if WebFetch hits Cloudflare 403 / rate limits |

## Output format

Always return:

```
## Research findings
<bullet list of facts gathered>

## Style prompt
<fenced code block, char count>

## Lyrics shell
<fenced code block with section tags>

## Tweak knobs
<3-5 ways to adjust>

## Confidence + sources
<HIGH/MEDIUM/LOW per claim, source URLs>
```

Don't dump raw research notes — synthesize into a usable prompt.
