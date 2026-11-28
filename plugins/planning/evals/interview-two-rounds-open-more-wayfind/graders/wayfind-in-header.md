---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Scope check: \d+ questions asked so far[^\n]*\n[^\n]{0,6}Wayfind:[^\n]*\bplanning:wayfind chart\b'
target: last_message
arm: both
---
