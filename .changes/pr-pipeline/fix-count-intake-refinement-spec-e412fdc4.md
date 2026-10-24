---
bump: minor
---

### Changed

- On an issue whose body a listed human wrote, and last edited if ever, intake triage's newest refinement comment (opening `<!-- intake-triage refinement -->`) by the lanes App now counts as spec while it is unedited: pr-verify's `resolve-pr.mjs` gives it to the verifier as spec text when it was posted before the pull request opened, and admission (`admit.mjs`) counts its task list for criterion 7. The lanes App is the trusted-actor list's id for `merge.agent-identity` in pr-verify and the list's id for the App's login in admission. An edited newest refinement counts nothing and no older one stands in for it; an App-filed issue, a body someone else last edited, a comment whose first text is not exactly the marker, and any other Bot's or App's comment stay out. A lane pull request still never supplies its own spec. The refinement stays out of the recorded spec comments the merge gate compares, whose filter stays human-only, so the gate does not see a refinement edited, hidden or added after a pass; an edit only removes it from spec. Intake's refinement banner and `refine.mjs`'s criteria check follow the rule.
