---
bump: patch
---

### Fixed

- **`research`: the verifier's row 12 also owns a sentence that restates a claim without its ID.**
  The restatement check finds a claim only by its ID, so a sidecar sentence that restates one claim
  on a line that cites another passed it. `artifact-shape.md` and the `research-verifier` agent now
  name that case beside ID-less table rows
  ([#13200](https://github.com/melodic-software/claude-code-plugins/issues/13200)).
