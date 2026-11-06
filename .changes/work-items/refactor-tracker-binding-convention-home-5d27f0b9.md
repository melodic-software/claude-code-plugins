---
bump: patch
---

### Fixed

- `/work-items:setup` gives the right reason for leaving the legacy `.work-item-tracker.json` files in place after it copies them into `<home>/work-items.yaml`: older installed plugin versions and the repository's own tooling may still read only them. It no longer names babysit-prs and the autonomy resolver, which now read the YAML binding first.
