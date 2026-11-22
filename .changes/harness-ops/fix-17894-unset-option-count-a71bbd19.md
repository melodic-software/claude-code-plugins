---
bump: patch
---

### Fixed

- `plugins` sync: an install's unset userConfig count comes from the `unsetOptionCount` field `claude plugin install --json` prints, so an install whose message lacks the count sentence still lands under "Action needed"; the required count is still read from the message.
