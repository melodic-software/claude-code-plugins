---
bump: minor
---

### Changed

- `/discovery:research`: "paper P reports X under conditions Y" now counts as a first-party content claim, accepted at `HIGH (single source)`, when P comes from the publisher authoritative on its topic: the publisher owns the product or system the result measures, such as an Anthropic paper on how Claude or its agents behave. The `single_source:` reason also names the publisher and the product it owns that P measured, so the verifier can grade it. A paper whose publisher does not own what it measured gets no flag: it is one source for X, which still needs two independent corroborators. X stated as a fact about the publisher or its product is a separate claim: the behavior-claim split and the single-publisher MEDIUM cap still apply to it. Two outcome-gate eval cases cover an authoritative paper's reports-claim, which is accepted, and a non-authoritative paper's, which is not. ([#7652](https://github.com/melodic-software/claude-code-plugins/issues/7652))
