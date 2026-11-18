---
bump: patch
---

### Fixed

- `/knowledge:video-digest` watch checks free space in the OS temp directory before it downloads media. It asks yt-dlp for the size of the formats it will select and exits 1 before any download when the temp directory has less than twice that free, naming the directory, the space needed and the space free. When no size is known, it warns and continues. The skill's gotchas describe setting `TMPDIR` for the whole session to stage on a larger disk.
