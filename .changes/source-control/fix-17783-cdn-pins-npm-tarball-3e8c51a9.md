---
bump: patch
---

### Fixed

- babysit-prs: the unattended CDN pins sync no longer trusts whatever jsDelivr serves. For each bumped package it now requires `lib/cdn-pins/package-lock.json` to lock that version at its canonical `registry.npmjs.org` tarball with a sha512 integrity, fetches the tarball, checks the sha512, and records the SRI hash only when jsDelivr's file equals `package/<file>` inside the tarball byte for byte. Any mismatch, missing entry or unreadable tarball exits 1 and writes nothing, as a jsDelivr 404 does.
