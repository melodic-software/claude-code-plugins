---
bump: patch
---

### Changed

- Skills refer to the legacy untrusted label by the `WIT_LEGACY_UNTRUSTED_LABEL` constant in `tools/work-item-tracker/lib/labels.sh` instead of writing out the string. They now link to `reference/label-taxonomy.md`, which links the class-labels reference. The frontier floor, the provenance-removal hold and the attended-queue flip rules still read the legacy label. The skill eval data no longer uses the dropped class labels.
