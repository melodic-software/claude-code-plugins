---
bump: minor
---

### Changed

- No path is held for being trusted alone (owner direction 2026-10-24): ci-status's `merge-holds.mjs` drops `HOLD_PATH_FLOOR` and the forced denied paths (the pipeline config and the trusted-actor list), and resolve-config no longer adds them to `merge.diff-check.denied-paths`. This repository sets `high-path-floor: false`. The trusted-actor widening hold and the review lanes still judge those paths.
- ci-status no longer holds a plugin or marketplace manifest change; the security lane flags it.
- `plugins/multi-agent/reference/defaults.yaml` is no longer a cost path; the infrastructure-as-code cost paths stay.
- A body hold (`Hold:` or "do not merge") counts only when a person wrote or edited the body, not the lanes App's own text.
- The verifier pass binds a link of no issue or of several: only a link that drops the judged issue holds it.
- `enable-auto-merge.mjs` comments on every refusal and adds the human-gated label only for a cause a person must clear: an untrusted spec, a security finding, a trusted-actor widening or a cost hold. A hold path, an issue link the lane does not take, a FAIL or the repeated-FAIL cap, and any other risk reason get the comment alone.
- `clear-escalations.mjs` takes that label off once the head moves under `merge.lane-prs: native` too, including a label put back under a standing escalation comment; the next run labels the new head again only if its cause still holds.
- `enable-auto-merge.mjs` reads a pull request's labels and its comments, reviews and review threads whole instead of refusing past 100, arms nothing and labels nothing when the resolved config does not read, and starts each run at an offset that moves with the run number, so the pull requests past the verify budget change from run to run.
