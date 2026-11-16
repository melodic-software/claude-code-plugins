---
type: regex
pattern: '<header\b(?:(?!</header>)[\s\S])*?\b(5|five)\b(?:(?!</header>)(?:<[^>]+>|[^<\n])){0,80}?\bcall(ers|[ -]sites)|<header\b(?:(?!</header>)[\s\S])*?\bcall(ers|[ -]sites)\b(?:(?!</header>)(?:<[^>]+>|[^<\n])){0,40}?\b(5|five)\b'
flags: i
match: not_contains
target: { source: file, path: deepening-report/report.html }
---
