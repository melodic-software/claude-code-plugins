---
bump: patch
---

### Security

- video-digest: vision-gated promotion refuses a `promotion-decisions.json` `sourceFile` that is not a bare file name, and resolves each promoted frame to its real path, refusing one that sits outside the frames directory (through `..` or a symlink) or is not a regular file. The copy then opens the checked frame with `O_NOFOLLOW` where the platform defines it and refuses it unless the open file is the same regular file the check passed, so a frame swapped for a symlink after the check is not copied. Before, such a value could copy a file from anywhere on disk into the slice. (#6979)
