---
bump: minor
---

### Added

- The pr-merge gate now trusts a verifier pass on a sub-issue that intake's size split filed, under the same rule Issue Triage admits it by. The sub-issue counts when the lanes App wrote it, a listed human filed its native parent in this repository, its body opens with the split header for that parent, and every task line is copied verbatim from the parent's listed-human text, or from intake's newest unedited refinement comment that the header names. A listed human's later edit of the sub-issue, such as a ticked box, also counts, but never in place of the named refinement's check. An outsider's parent, an edit by anyone else, a superseded, edited, updated or deleted refinement, a line found in neither source, a parent with more than 100 comments, or a failed read leaves it `verify:untrusted-spec`. The gate reads the sub-issue, its parent and the parent's comments in one GraphQL call under the job's Actions token, and only for an issue the lanes App wrote. The rule is checked against the shared `split-child.vectors.json` cases.
