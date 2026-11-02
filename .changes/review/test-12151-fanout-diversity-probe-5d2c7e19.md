---
bump: none
---

### Changed

- The `fanout-diversity-*` eval cases carry #12151's probe result in their descriptions: `lens` and `model` both named every planted defect (24/24), so `lens` stays the default, and the Codex arms are not measurable under codex 1.0.6.
- Their arm check accepts the `repository` layer label fanout writes, the recall and false-positive graders carry three borderline calibration samples each, and `fanout-diversity.md` names the run flags the result depends on (`--allow-tools Bash Write Workflow`, a `TMPDIR` outside `/tmp` and `/var/tmp`, a staged target for the multi-plugin cases).
