---
bump: patch
---

### Changed

- **pr-verify PASS and PASS-NOTES artifacts now expire after 7 days instead of 30, unless the pull request's body or issue links changed since its head commit.** Such a pass is read only at an open pull request's current head, so outliving that head is dead weight in the repository-wide artifact listing; a pass that expires on a held head fails closed as `verify:missing` and the next push, edit or label has pr-verify judge it again. A pass judged after a body edit or link change may supersede a FAIL at its head, which the merge gate still reads at a later merge-only head, so it keeps 90 days like the FAIL. FAIL verdicts keep 90 days for the 80-day look-back. The `pr-review-main-*` row records why its 90 days stay for now.
