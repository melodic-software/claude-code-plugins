---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Scope check: \d+ questions asked so far[^\n]*\n(?:(?![^\n]{0,6}(?:❓[^\S\n]*)?Q\d+\b)[^\n]*\n)*?[^\n]{0,6}Open:[^\n]*\b(?:alert|alerted|PagerDuty|on-call)\b[^\n]*\n(?:(?![^\n]{0,6}(?:❓[^\S\n]*)?Q\d+\b)[^\n]*\n)*?[^\n]{0,6}Next round \(over the cap of 4\):[^\n]*\n(?:(?![^\n]{0,6}(?:❓[^\S\n]*)?Q\d+\b)[^\n]*\n)*?[^\n]{0,6}Later:[^\n]*\breplay\b[^\n]*\n(?:(?![^\n]{0,6}(?:❓[^\S\n]*)?Q\d+\b)[^\n]*\n)*?[^\n]{0,6}(?:❓[^\S\n]*)?Q\d+\b'
flags: i
target: last_message
arm: both
---
