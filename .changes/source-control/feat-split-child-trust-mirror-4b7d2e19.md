---
bump: minor
---

### Added

- The pr-merge gate now trusts a verifier pass on a sub-issue that intake's size split filed, under the same rule Issue Triage admits it by. The sub-issue counts when the lanes App wrote it, a listed human filed its native parent in this repository, its body opens with the split header for that parent, and either nobody edited it and every line after the header is one of the parent's trusted task-list lines, or a listed human last edited it, such as by ticking a box. A trusted task-list line is a line of the parent's listed-human body or comments that starts with admission's `task-list` prefix, read from `admission-rules.json` at the base branch; a prose line or heading copied from the parent does not count, and a missing or empty prefix counts nothing. An outsider's parent, an edit by anyone else, a line not among the parent's task lines, or a parent with more than 100 comments leaves it `verify:untrusted-spec`, and a failed read of the sub-issue, its parent or the rules refuses `verify:unreadable`. The gate reads the sub-issue, its parent and the parent's comments in one GraphQL call under the job's Actions token, and the rules once, only for an issue the lanes App wrote. The rule is checked against the shared `split-child.vectors.json` cases.
