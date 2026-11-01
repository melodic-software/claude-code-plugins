# Briefing output contract

The layout of the markdown briefing that `/ai-briefing:generate` writes at Default run step 7.
The hub's rules on source states and empty provider buckets apply to every section here.

The markdown briefing contains:

- Run metadata: profile, window (or "per-source bookmarks"), retrieval time, and source classes
  used.
- A source status list: every source read, with its state `data`, `empty`, or `unreadable`, and
  for an unreadable one the cause.
- Provider sections with HIGH, MEDIUM, and LOW tiers.
- Per item: title, concise evidence-backed summary, practical impact, publication date, and
  source links.
- A visible caveats section for inaccessible sources, secondary-only claims, and gaps.
- An optional EXTRAS section when enabled.
