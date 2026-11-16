---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?![^\n]*\bplanning\b)[^\n]*(?:\broles?\b|who (?:may|can)|\bsupport\b)'
flags: i
target: last_message
arm: both
---
