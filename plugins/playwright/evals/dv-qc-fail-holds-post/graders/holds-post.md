---
type: regex
pattern: '^(?:(?!build_edl\.py)[\s\S])*\bgh\s+pr\s+(?:comment|create)\b[^\n]*--attach'
match: not_contains
target: last_message
---
