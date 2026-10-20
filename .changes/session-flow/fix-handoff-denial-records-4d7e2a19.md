---
bump: minor
---

### Changed

- `handoff` Constraints entries that record a permission or auto-mode refusal, or an owner-reserved step, carry the session, date and verbatim denial text (or the owner's quoted words); a resumed session retries a recorded refusal once in its documented shape before handing the action to the user, and a lifted reservation moves under `Superseded:`.
- `handoff` Remaining actions list prework (review a peer's PR, check a release, pre-verify the awaited condition) when every action waits on a peer or the owner, instead of a bare "no action owed" line.
