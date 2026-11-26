---
type: regex
pattern: '(?:^|\n)[^\S\n]*(?:#{1,6}[^\S\n]+|\*\*)(?:Retr(?:y|ies)|Alert(?:s|ing)?)\b[^\n]{0,30}(?:\*\*)?[^\S\n]*(?:\n|$)'
flags: i
match: not_contains
target: last_message
arm: both
---
