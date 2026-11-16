---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?![^\n]*\bplanning\b)[^\n]*(?:calendar month|date range|chosen month|export cover|export contain)'
flags: i
target: last_message
arm: both
---
