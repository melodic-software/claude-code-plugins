---
bump: minor
---

### Added

- **Planted-defect eval fixture.** `evals/fixtures/ui-defects/` holds one static product page and `build-variants.py`, which writes eleven variants under opaque ids: nine planted defects (overlap, clipping, low contrast, missing image, layout shift, off-by-one count, console error, misalignment, off-viewport), a clean control and a benign change. Variants load only from `file://` and rebuild byte for byte.
- **Check-layer harness.** `harness/measure-layers.mjs` renders every variant in Chromium at 375 and 1280 px and records which layer catches each defect (axe, geometry, layout shift, pixel diff, console, DOM, aria snapshot), with no model calls. `harness.test.sh` compares the result with `expected-matrix.json`; it skips when the one-time install in its README is missing, and `UI_DEFECTS_REQUIRE=1` makes that skip a failure.
- **Vision eval cases.** Nine `vision-*` cases give a model the committed screenshots of one variant and grade whether it reports the planted defect: the verdict line, a defect-term grader that counts only an asserted finding, reads at both widths, and a grader that fails a run reading the eval cases or the variant map. `crops/render-crops.mjs` re-renders the screenshots byte for byte.
