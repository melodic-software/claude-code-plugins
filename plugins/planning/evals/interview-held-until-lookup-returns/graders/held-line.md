---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Open:(?![^\n]*\bQ\d)[^\n]*\b(?:who|alerted|alerting|routing|channel|page[sd]?|paging|PagerDuty|on-call)\b'
flags: i
target: last_message
arm: both
---
