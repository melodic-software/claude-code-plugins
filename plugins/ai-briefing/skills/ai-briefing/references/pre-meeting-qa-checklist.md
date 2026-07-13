# Pre-meeting QA checklist (manual, T-24h before meeting)

Run this checklist Thursday night (or the equivalent T-24h slot) before the next AI meeting. The manual checklist is intentionally human-driven — no code automation yet. Planned follow-ups: automated review action (`/ai-briefing:ai-briefing review --links --research --reorder --dedup`) and retro metrics (`/ai-briefing:ai-briefing retro --meeting N`) ship after empirical data from running this manual loop across ≥2 meetings.

## When to run

| Trigger | Action |
|---|---|
| ~24h before scheduled AI meeting | Walk every step below in order |
| User invokes `/ai-briefing:ai-briefing --meeting-prep` | Skill displays a reference to this file at run start |
| Suspicious gap detected in coverage (broken-link spike, profile silent) | Spot-walk steps 2 + 5 only |

## Checklist (10 steps)

```text
[ ] 1. Final scrape (T-24h)
       /ai-briefing:ai-briefing --since 2d --add-only
       → Catches Wed/Thu ships
       → Surface profiles silent ≥2 runs (failure-mode alert)

[ ] 2. Link health pass
       Inspect output/build/shots/audit.json broken-link findings:
       → 4xx → drop URL from meeting-{N}.md (preserve body text + alt source if available)
       → 429/403 → leave (auth-gated, not authoritative broken)
       → 5xx → retry once, then drop
       → Cross-source > 1 = boost, single-source = flag

[ ] 3. Content recency re-research
       For each HIGH item: 1× perplexity_ask + 1× WebSearch
       → "Has X been updated since [date]?"
       → "Is X still in beta or did it GA?"  (beta → GA tracker)
       → "Any deprecation news / breaking changes?"
       → Update body text if drift detected

[ ] 4. Audience-relevance ordering
       Re-rank HIGH/MED/LOW per "engineer week-of action" lens:
       → Will engineer install/use this next week? → HIGH
       → Cost/access economics shift? → HIGH
       → Industry-wide regulatory? → HIGH
       → Speculation/research/vibe? → LOW

[ ] 5. Dedup against prior meetings
       grep prior meeting-{N-1..N-3}.md for repeat items:
       → 2+ meetings without change → demote to LOW or drop
       → Mention with update → "[update]" prefix on title

[ ] 6. "Would audience act on this?" pass
       Read meeting-{N}.md top-to-bottom in audience persona.
       For each HIGH bullet:
         YES, would act next week → keep HIGH
         MAYBE → demote MED
         NO → demote LOW or drop
       → Record judgment in retro.md (when retro action ships)

[ ] 7. Visual rebuild + inspect
       cd output/build && node run.js && node validate.js
       → Review screenshots, audit.json warnings, headline truncations
       → Run Gate 7 responsive matrix (6 viewport×zoom combos)
       → Surface any new layout breaks

[ ] 8. Final dry-run
       Open HTML fullscreen, click through every section
       → Time it: target 15-20min for news block
       → If >30min: cut LOW items
       → Verify chip nav, hash-deep-link, prev/next buttons

[ ] 9. Mobile/zoom dry-run
       Ctrl+wheel zoom 100% → 150% → 200% in browser
       → Spot-check each section reflows cleanly
       → Open on phone (or DevTools mobile emulator)
       → Scroll through entire deck

[ ] 10. Ship
       cp output/meetings/ai-meeting-{N}.{html,pdf,pptx} <presentation-surface>
       → Notify presenter (if not the runner)
       → Tag commit + push
```

## Gate semantics

- **Blocking (MUST resolve before ship):** broken-link rate >5%, headline truncation that cuts mid-word, layout overflow on non-decorative section, news block exceeds 30min read time.
- **Warning (note, ship anyway):** auth-gated 429/403 (real source), single-source HIGH item with no cross-confirmation, Flair slot empty.

## Planned automation (not yet shipped)

**Automated review action** — codify steps 2-5 as `/ai-briefing:ai-briefing review --links --research --reorder --dedup`. Triggered after ≥2 meetings of manual baseline (target: meetings #21 + #22).

**Retro metrics action** — `/ai-briefing:ai-briefing retro --meeting N` interactive capture records audience signal per item (acted/noted/skipped), writes retro-{N}.md, updates `audience_signal` on items in seen-items.json, surfaces patterns ("Cursor items always acted on" / "DeepSeek items never acted on"). Triggered after automated review stabilizes.

## Cross-references

- `pre-execution-gate.md` "Pre-execution confirmation gate" — fires before any wave runs
- `execution-flow.md` "Step 6.5: Verify checklist (MANDATORY GATE)" — done-gate at end of run
- `references/checklist-system.md` — programmatic per-run coverage checklist (different from this manual one)
- `output/build/validate.js` Gate 7 — responsive matrix verification (step 7 above invokes this)
