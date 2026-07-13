# Enrichment passes (Step 4.5)

Optional enrichment passes that extend Step 4 (Categorize and rank) BEFORE 13-bucket output is finalized. Each pass is opt-in via standing default — drop into Step 4 normally and let the pass mutate items.

## Table of contents

- Fact verification gate (HIGH items)
- Repo-aware research lens (impact tag)
- Sentiment / hype-discount filter
- "What's missing" check (negative space)

## Fact verification gate (HIGH items)

For each HIGH item, verify body text against FIRST source URL:

1. WebFetch the URL
2. Grep returned content for key claim from body text (e.g., "5h limits doubled", "Opus 4.8 GA")
3. If claim absent or contradicted → flag `[VERIFY]` prefix on title; demote to MED until human review
4. If claim confirmed by current page → leave as-is

Catches drift between aging tweet headlines and current product reality (e.g., tweet says "free" but article now says "free for Pro tier only").

## Stack-aware research lens (impact tag) — profile-provided, optional

Runs only when the active profile supplies a tech-stack lens (see `references/audience-defaults.md` "Profile-provided impact lens"). With no profile stack lens, skip this pass. When present, for each HIGH item:

1. Read the profile's stack signals (its declared language/runtime, database, auth, hosting, AI-integration surface)
2. Per-item annotation: `impact: high|medium|low|none + 1-line reason`
3. Render as small italic tag below body in news bullets

Examples:

- "Agent-loop feature → impact: medium — could automate our webhook integration testing"
- "New open-weight model → impact: low — no current use case in our stack"

Schema field: `impact` per item in `seen-items.json` (optional).

## Sentiment / hype-discount filter

S3 synthesis applies sentiment classifier. Marketing-heavy posts ("revolutionary", "game-changing", "blowing my mind", "completely changes everything") get reformulated:

1. Strip superlatives from body text
2. Reduce to factual claims only ("X feature added", "Y limit raised from N to M", "Z model GA")
3. Track ratio of marketing-heavy posts per provider as drift signal — if vendor's posts are >50% marketing-tone, flag in next drift report

Engineering audience trusts factual content; superlatives erode signal.

## "What's missing" check (negative space)

After scrape completes, run for each top-level provider:

```text
WebSearch / Perplexity: "Major releases from {provider} in the past 14 days"
```

Cross-check returned items against captures:

1. If a release is mentioned by ≥2 external sources but NOT in our captures → flag as missed item
2. Add to next-run priority list with `[CATCH-UP]` prefix
3. Investigate scrape gap — handle silent? Twitter cap hit? Wave 1.5 needed?

Catches systematic capture gaps that per-profile checks miss (e.g., a vendor announces via blog only, no Twitter coverage).
