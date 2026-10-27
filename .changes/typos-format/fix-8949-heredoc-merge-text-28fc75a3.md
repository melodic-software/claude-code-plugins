---
bump: patch
---

### Changed

- hook-utils: `hook::bash_parse_segments` leaves the byte span of each here-doc body it skips in `HOOK_HEREDOC_BODIES`, along with whether its delimiter was quoted, so a guard can tell a quoted body's text from the commands around it (#8949). A here-doc delimiter word now ends at `(` or `)`, as it does in bash.
