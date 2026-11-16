---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?![^\n]*\bplanning\b)[^\n]*(?:background|request|when (?:it''?s|the file is) ready|finished file|time ?out|stream|chunk|40,000|large export)'
flags: i
target: last_message
arm: both
---
