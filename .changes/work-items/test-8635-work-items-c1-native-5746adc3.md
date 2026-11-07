---
bump: patch
---

### Changed

- The decompose `evals.json` file is retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Thirteen new `decompose-` cases cover vertical slices with AFK and HITL classes in blocker order, source item text as data, the prefactor and integrate-and-verify fallback, the PR variant, expand-migrate-contract, the spec container offer and execution shape, a mid-flight reroute, native issue types, inlined decisions without coined ids, the Brief's intent and assumptions, a demo line per slice, and one slice per behavior. Each is a described run graded on the reply; the existing `decompose-no-container-carries-brief` case already covers legacy case 8.
