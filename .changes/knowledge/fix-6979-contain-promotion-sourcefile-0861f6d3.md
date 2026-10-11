---
bump: patch
---

### Security

- video-digest: vision-gated promotion refuses a `promotion-decisions.json` `sourceFile` that is not a bare file name, and resolves each promoted frame to its real path, refusing one that sits outside the frames directory (through `..` or a symlink) or is not a regular file. Before, such a value could copy a file from anywhere on disk into the slice. (#6979)
