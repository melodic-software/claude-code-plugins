---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?![^\n]*\bplanning\b)[^\n]*(?:export(?: file)? (?:cover|contain|hold)|date range|one calendar month|a whole calendar month|chosen month)'
flags: i
target: last_message
arm: both
---
