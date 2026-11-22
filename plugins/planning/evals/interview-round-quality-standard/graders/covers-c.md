---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?![^\n]*\bplanning\b)(?:(?:(?!\n[^\n]{0,6}Q\d+:|\bsomething else\b)[\s\S])*?\n[^\S\n]*(?:(?:➡️[^\S\n]*)?[*_]{0,2}(?:My recommendation|Withheld|Discovery|Flips if)\b|- \([a-z]\)))?[^\n]*(?:\broles?\b|who (?:may|can)|\bsupport\b)'
flags: i
target: last_message
arm: both
---
