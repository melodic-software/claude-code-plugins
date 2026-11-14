---
type: regex
pattern: 'code-metrics:audit|review:quality-gate|\bnot\s+(been\s+)?assessed\b|\bunassessed\b'
flags: i
target: last_message
---
