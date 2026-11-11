---
bump: patch
---

### Fixed

- `ask_secret` warns when an answer reaches the terminal's line limit (4,095 bytes on Linux, 1,023 on macOS; past it a pasted line is cut with no error) and offers to read the whole value from a file path. Enter keeps the pasted value; an unreadable file, or one holding more than one line, aborts. Before, a long one-line secret such as a signing key or JWT could be saved cut off with no warning.
