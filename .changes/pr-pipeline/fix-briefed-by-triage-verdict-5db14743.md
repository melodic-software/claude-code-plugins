---
bump: minor
---

### Changed

- pr-verify also takes the body of an issue the lanes App filed as its spec when intake-triage's own verdict briefed it: the lanes App's verdict comment (`<!-- intake-triage verdict -->`, by its account id, last edited by no other account) says the triage verdict holds nothing because the issue is ready or admission moved it, and its last line names the issue's current title and body by sha256. The verdict writer stamps that line on a ready verdict whose body was not edited after the triage run judged it. A held verdict, one a person's Work status set holds, one admission did not finish, or one waiting on a blocked-by edge counts nothing, and the veto set from the admission-record rule still applies.
