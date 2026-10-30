---
bump: patch
---

### Added

- **Routing eval: review cases.** Five cases under `evals/routing/review/` cover code review and verification with code from this repository. Three `rv-*` cases ask for the defect a diff introduces, a seeded defect beside a behavior-preserving decoy edit, in Bash, Python and JavaScript. Two `vf-*` cases ask whether each of four review findings is confirmed or refuted, two of them false. Every grader is a deterministic regex with must-pass and must-fail samples, so no judge model scores a run. Their README gives the arm configuration (model and effort level) for each setup the paired routing eval compares ([#10012](https://github.com/melodic-software/claude-code-plugins/issues/10012), part of [#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901)).
