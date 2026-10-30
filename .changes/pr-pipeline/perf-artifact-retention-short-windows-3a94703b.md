---
bump: patch
---

### Changed

- **pr-verify PASS and PASS-NOTES artifacts now expire after 7 days instead of 30.** Every reader takes a pass only at an open pull request's current head, so a pass outliving that head is dead weight in the repository-wide artifact listing; a pass that expires on a held head fails closed as `verify:missing` and the next push, edit or label has pr-verify judge it again. FAIL verdicts keep 90 days for the 80-day look-back. The `pr-review-main-*` row records why its 90 days stay for now.
