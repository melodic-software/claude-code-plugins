---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?![^\n]*\bplanning\b)(?:(?:(?!\n[^\n]{0,6}Q\d+:|\bsomething else\b)[\s\S])*?\n[^\S\n]*(?:(?:➡️[^\S\n]*)?[*_]{0,2}(?:My recommendation|Withheld|Discovery|Flips if)\b|- \([a-z]\)))?[^\n]*(?:background|(?:after|in|inside|outside|within|during) (?:the|a) (?:(?:web|same|click''s own) )*(?:request|click)|(?:when|once) (?:(?:it''?s|it is|the file is) )?ready|times? ?out|stream|chunk|40,000|large export)'
flags: i
target: last_message
arm: both
---
