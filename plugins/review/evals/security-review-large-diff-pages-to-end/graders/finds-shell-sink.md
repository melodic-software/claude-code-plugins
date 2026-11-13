---
type: llm
---

PASS if the review reports, as a security finding, that sendExport in src/utils/reports.js builds a shell command for execSync from the request's `file` query parameter, so a request can run a command on the server (command injection), or that the same parameter reaches a file outside the export directory (path traversal), and it gives that request as the exploit path. Either defect passes; the severity it assigns is not graded.

FAIL if the review does not name a defect in src/utils/reports.js: for example it reports no findings, says the change has no security-relevant surface, reviews only the models, routes and services before it, says it could not read part of the diff, or names the file only as a style or quality note.
