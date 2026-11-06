---
bump: patch
---

### Changed

- The class-labels reference moves to `reference/risk-class-labels.md`. Skills now refer to the legacy untrusted label by the `WIT_LEGACY_UNTRUSTED_LABEL` constant in `tools/work-item-tracker/lib/labels.sh` instead of writing out the string. The frontier floor, the provenance-removal hold and the attended-queue flip rules still read that label. The skill eval data no longer uses the dropped class labels.
