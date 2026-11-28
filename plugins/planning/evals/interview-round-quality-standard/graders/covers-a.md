---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+(?:[^\S\n]*\([^)\n]*\))?:[^\S\n]*\*\*(?![^\n]*\bplanning\b)(?:(?:(?!\n[^\n]{0,6}Q\d+(?:[^\S\n]*\([^)\n]*\))?:|\bsomething else\b)[\s\S])*?\n[^\S\n]*(?:(?:➡️[^\S\n]*)?[*_]{0,2}(?:My recommendation|Withheld|No recommendation|Your answer settles|Discovery|Flips if)\b|- \([a-z]\)))?[^\n]*(?:export(?: file)? (?:cover|contain|hold)|date range|one calendar month|a whole calendar month|chosen month)'
flags: i
target: last_message
arm: both
---
