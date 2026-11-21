---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}(?:\*\*)?Held(?:\*\*)?:[^\n]*\b(?:who|alerted|alerting|routing|channel|page[sd]?|paging|PagerDuty|on-call)\b'
flags: i
target: last_message
arm: both
---
