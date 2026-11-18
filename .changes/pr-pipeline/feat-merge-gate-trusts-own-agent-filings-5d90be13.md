---
bump: minor
---

### Changed

- The merge gate trusts an own-agent filing intake admission admits as a pull request's spec, so a lane pull request built from one merges with no person: an identity on main's `own-agents` list wrote it, no other account edited its body, it carries exactly one `source: <producer>` label, and a listed human or the lanes App sized it small or medium.
