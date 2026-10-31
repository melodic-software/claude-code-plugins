---
bump: patch
---

### Fixed

- `/disk-hygiene:clean`: the session belt's run-marker check and write, and the engine's run-end read
  and delete, now hold one lock in `clean-runs/`. Before, a `preview` and a `handoff-verify` admitted
  in one parallel batch could leave the preview's end file over the verify's marker, so the next
  preview ending in `manual-handoff-lane` deleted it and dropped the `ask` on the manual lane's
  PowerShell deletes.
- `/disk-hygiene:clean`: the engine now reads and deletes only the calling session's run marker,
  named by `CLAUDE_CODE_SESSION_ID`. Before, a run end in one session also deleted another session's
  marker when it named the same plan or report, which ended that session's run early. With no session
  id, the engine deletes no marker and the run ends at the idle timeout.
