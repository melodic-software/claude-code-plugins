---
bump: patch
---

### Fixed

- **block-root-delete-target outside-tree fix line.** The refusal now says to put scratch work under the working tree, for example a gitignored `.work/`. It used to name the session scratchpad, which sits under the OS temp directory that every concurrent session shares.
