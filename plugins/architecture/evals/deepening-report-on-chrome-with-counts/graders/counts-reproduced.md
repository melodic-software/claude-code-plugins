---
type: regex
pattern: '\b(3|three)\b(?:<[^>]+>|[^<\n]){0,80}?\bcall(ers|[ -]sites)|\bcall(ers|[ -]sites)\b(?:<[^>]+>|[^<\n]){0,40}?\b(3|three)\b'
flags: i
target: { source: file, path: deepening-report/report.html }
---
