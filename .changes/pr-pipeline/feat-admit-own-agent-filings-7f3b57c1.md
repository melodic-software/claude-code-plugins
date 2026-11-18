---
bump: minor
---

### Changed

- Intake admission takes an own-agent filing with no person (ADR 0111). `own-agents` in `admission-rules.json` lists the identities, by default the lanes App alone; github-actions[bot] stays trusted only for upstream-drift issues. Such a filing is admitted only at Size small or medium, with exactly one `source: <producer>` label, and with its body unedited by any other account, which then counts as its spec in admission and in pr-verify. Size large, a patch over the scan cap, a missing `source:` label or another account's edit holds it for a listed human, and it is never split automatically. It waits at `status: ready` while `own-agents.source-cap` (default 5) or more older open issues carry its `source:` label. A listed human's issue is admitted as before.
