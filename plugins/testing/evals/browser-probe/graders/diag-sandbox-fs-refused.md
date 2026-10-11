---
type: regex
target: trace
match: not_contains
weight: 0.001
pattern: 'bwrap: |Operation not permitted|Read-only file system|EROFS|EACCES|EPERM|Permission denied|ERR_ACCESS_DENIED|ERR_FILE_NOT_FOUND(?! at file:[^"\s]*peek[/\\]+canary\.html)'
---
