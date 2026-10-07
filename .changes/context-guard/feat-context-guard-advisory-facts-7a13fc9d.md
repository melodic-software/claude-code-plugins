---
bump: minor
---

### Changed

- **Every line context-guard sends Claude states facts only.** The dumb zone no longer carries a default save-state note (`zones.json` actions now default to `none` in every zone), a line with figures no longer ends "Continuing is the user's call.", a `save-state` or `handoff` action without `text` names the action instead of advising one, the blocking gate's denial no longer points at `/session-flow:handoff`, and the `status` tool's description no longer says when to call it or not to poll it. Zone computation, bands, the gate's default (advisory) and the post-compaction dumb verdict are unchanged.

### Fixed

- **The band provenance no longer claims measured per-length data for current models.** The reader contract and the 0.13.0 entry said 128K was the last length at which a current Claude model was measured strong on long-context retrieval and cited AUC figures; no per-length data is published for Opus 5.5, Sonnet 5.5 or Fable 5.1. The reader contract now gives the published figures the edges are anchored on: Context Arena 8-needle MRCR for Claude Opus 5 and Sonnet 5, and Google's GraphWalks BFS run of Fable 5.1.
