---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?![^\n]*\bplanning\b)(?![^\n]*\bcolumns?:)[^\n]*(?:currenc|cents|decimal|amounts? (?:be|appear|written|shown|formatted))'
flags: i
target: last_message
arm: both
---
