---
bump: patch
---

### Fixed

- intake-triage's split of a held issue no longer edits the issue body. The lanes App's refinement comment now records the done-when items a person runs and the body they number (`<!-- split items=N -->` beside the body hash), and admission and pr-verify read that record (admit.mjs `personChecks`): admission leaves those items out of its unrunnable and unpushable checks while they are exactly the items the lane cannot perform, a size split leaves them out of its parts, pr-verify passes them to the verifier as `person_checks` beside the body, which stays as its author wrote it, and the issue lane's `issue.json` carries them the same way. Each reader honors the record only under admission's guards (the refinement counts as spec, names the body's hash, and lists exactly the items the lane cannot perform under the issue lane's configured web hosts); a split refinement whose record does not stand reaches neither the verifier nor the lane, so its prose excuses nothing. Before, the App's body edit made it the body's last editor, so pr-verify no longer trusted the body and the issue lost its spec ([#9372](https://github.com/melodic-software/claude-code-plugins/issues/9372)). pr-verify's trust rule is unchanged.
