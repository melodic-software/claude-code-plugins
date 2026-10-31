---
bump: minor
---

### Changed

- The book distillation skill is now `/knowledge:distill`; invoke it by that name. Its description names its two sources, a PDF or EPUB book and an author's published web corpus, and states that it writes skill reference files only. Its eval cases are `distill-target-name-slugified` and `distill-traversal-epub-aborts`, and its probe file is `probes/distill.json`.
