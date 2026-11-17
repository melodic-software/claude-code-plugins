---
bump: patch
---

### Fixed

- `check-restatement-labels.py --sub-slice` now grades a fan-out whose sub-slices reuse a claim ID instead of exiting 2. Each sub-slice's IDs are namespaced by its directory name: a root line may cite `<sub-slice>/X2` for one sub-slice's claim, and a bare `X2` must carry the label of every claim declaring it. An ID declared twice in one sub-slice, a root claim that reuses a sub-slice ID, and two sub-slices sharing a directory name still exit 2. The research dispatch reference and the research verifier no longer describe the verifier fallback for a cross-sub-slice ID collision.
