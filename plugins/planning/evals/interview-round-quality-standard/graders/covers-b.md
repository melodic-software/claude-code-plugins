---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?![^\n]*\bplanning\b)(?![^\n]*\bcolumns?:)(?:(?:(?!\n[^\n]{0,6}Q\d+:|\bsomething else\b)[\s\S])*?\n[^\S\n]*(?:(?:➡️[^\S\n]*)?[*_]{0,2}(?:My recommendation|Withheld|Discovery|Flips if)\b|- \([a-z]\)))?[^\n]*(?:currenc|cents|decimal|amounts? (?:be|appear|written|shown|formatted))'
flags: i
target: last_message
arm: both
---
