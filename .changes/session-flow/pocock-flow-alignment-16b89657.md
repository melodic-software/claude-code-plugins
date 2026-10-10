---
bump: minor
---

### Changed

- `/session-flow:workflow` adds a quick-change on-ramp: a change whose diff is quick to review and cheap to retry enters at implement and is aligned on its diff, returning to the interview if the diff is not quick to review; a diff that adds types, public contracts or module boundaries is not cheap to retry and takes the full path. New work whose diff fails either test starts at the contract interview (after the PRD when its trigger holds), with explore and research as detours it triggers, and that fresh-start suggestion takes precedence over the earlier-stage tie-break. A too-big, foggy effort reaches wayfinding only as an escalation from that interview. The design and contract skip rules now govern the full path only. Position detection places a session that began at an entry skill (explore, research, blindspot, brainstorm, debug, triage, an interview) on the ladder from its evidence.
