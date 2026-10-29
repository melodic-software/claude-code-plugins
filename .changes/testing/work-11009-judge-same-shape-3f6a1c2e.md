---
bump: minor
---

### Changed

- **`/testing:audit --judge` gives tests of one shape one verdict** ([#11009](https://github.com/melodic-software/claude-code-plugins/issues/11009)). Before dispatching, the judge pass computes a shape key for every block with the new `skills/audit/scripts/judge-check.sh shape`. Blocks with the same key have the same body apart from the test's name, the same lines around them in their file, and the same judge class and effort. The judge sees only the first block of each key, and the others take its verdict, reported as `same shape as <path>:<start> <name>`. Before, each file got its own judge run, so identical tests could come back FLAG in one file and PASS in another.
- **A comment-only repair is now caught by a script.** The judge pass runs `judge-check.sh comment-only` on each FLAG's proposed diff. When every line the diff adds or removes is blank or a comment, the verdict turns UNKNOWN. This check used to be the orchestrator's own reading of the diff. It applies the comment syntax of the scanner adapters' languages, from the same `judge-lib.sh` function the calibration harness uses.
