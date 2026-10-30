---
bump: patch
---

### Changed

- Golden case `c26` is now recorded as verbatim on lines 7-10, by the owner's ruling of 2026-10-30 on its 2-1 rubric v5 panel split ([#5654](https://github.com/melodic-software/claude-code-plugins/issues/5654#issuecomment-6523541851)). Re-scored from the stored judge outputs, with no judge re-run: verbatim moves from n 3, recall 1.00 to n 4, recall 0.75 (the split panel emits no finding, so c26 is its one false negative), and stays report-only below `min_n_per_class` 10; near-verbatim moves from n 13, recall 0.92 to n 12, recall 1.00, still binding. Precision is 1.00 in both classes, and the overall 22 / 3 / 1 / 12 is unchanged. No class is declared fix-eligible.
