---
bump: minor
---

### Changed

- **The babysit merge gate trusts the own-agent filings intake admission admits.** A pr-verify pass whose linked issue an identity on admission's `own-agents` list wrote now counts as a trusted spec when no other account edited the issue's body, the issue carries exactly one well-formed `source: <producer>` label, and a listed human or the lanes App sized it small or medium. The gate reads the list from the default branch and each condition live. Any other filing still reads `verify:untrusted-spec`, a failed read reads `verify:unreadable`, and github-actions[bot] never counts as an own-agent identity, even when the list names it.
