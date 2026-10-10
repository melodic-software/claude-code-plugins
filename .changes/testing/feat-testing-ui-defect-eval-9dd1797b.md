---
bump: minor
---

### Added

- **Planted-defect eval fixture.** `evals/fixtures/ui-defects/` holds one static product page and `build-variants.py`, which writes eleven variants under opaque ids: nine planted defects (overlap, clipping, low contrast, missing image, layout shift, off-by-one count, console error, misalignment, off-viewport), a clean control and a benign change. Variants load only from `file://` and rebuild byte for byte.
- **Check-layer harness.** `harness/measure-layers.mjs` renders every variant in Chromium at 375 and 1280 px and records which layer catches each defect (axe, geometry, layout shift, pixel diff, console, DOM, aria snapshot), with no model calls. `harness.test.sh` compares the result with `expected-matrix.json`; it skips when the one-time install in its README is missing, and `UI_DEFECTS_REQUIRE=1` makes that skip a failure.
- **Vision eval cases.** Nine `vision-*` cases give a model the committed screenshots of one variant and grade whether it reports the planted defect. Deterministic graders check structure only: the verdict line, a tagged FINDING line with a real body (or, in the two controls, no FINDING line), reads at both widths, and no read of the eval cases or the variant map. An LLM judge per case checks meaning: it passes only a reply that asserts the planted defect with its location, fails a denial or a hedge, and passes a control only when it reports no defect. `crops/render-crops.mjs` re-renders the screenshots byte for byte.
