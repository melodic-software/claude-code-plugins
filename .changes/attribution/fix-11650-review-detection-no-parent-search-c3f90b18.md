---
bump: patch
---

### Fixed

- `/attribution:audit` detects the `review` plugin for its findings contract by whether `/review:fanout` resolves in the session, and never globs or lists outside its own plugin root to find it. It reads `review`'s bundled files only when the session already knows that plugin's root; otherwise it uses the publisher's raw URL. A session with `review` installed but its root unknown therefore now needs the network for the contract, and offline it is report-only. A path link into the `review` plugin's tree is replaced by a `/review:fanout` reference.
