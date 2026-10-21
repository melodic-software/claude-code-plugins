---
bump: minor
---

### Added

- New `storage-top-n` check (category `storage`, no admin): lists the 15 largest folders directly under `%USERPROFILE%` and under the reclaim locations (`%TEMP%`, your Recycle Bin, `%ProgramData%\Package Cache`, `Windows.old`), each as a mutable INFO item with its logical size, its allocated size when it holds at most 10,000 files, and a reclaim hint. The scan never descends a OneDrive sync root or any other junction or symlinked folder and never opens a file for its content, so cloud-only files are not downloaded; each skipped sync root is listed as "skipped: cloud sync root". One 60-second budget covers the whole scan; a cut scan says so in `scan_complete`.
