---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?![^\n]*\bplanning\b)[^\n]*(?:background|(?:after|in|inside|within|during) the (?:(?:web|same|click''s own) )*(?:request|click)|(?:when|once) (?:it''?s|it is|the file is) ready|time ?out|stream|chunk|40,000|large export)'
flags: i
target: last_message
arm: both
---
