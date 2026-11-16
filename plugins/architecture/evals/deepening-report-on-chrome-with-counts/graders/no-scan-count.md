---
type: regex
pattern: '\b(5|five)\b(?:<[^>]+>|[^<\n]){0,80}?\bcall(ers|[ -]sites)|\bcall(ers|[ -]sites)\b(?:<[^>]+>|[^<\n]){0,40}?\b(5|five)\b'
flags: i
match: not_contains
target: { source: file, path: deepening-report/report.html }
---
