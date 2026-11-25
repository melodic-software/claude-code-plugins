---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?start\b|\bneeds? an interactive session\b|\brefus(?:e|es|ing) to chart\b|\b(?:cannot|can''t|won''t|will not|unable to) chart\b|\btoo (?:big|foggy|large) to chart\b|(?:^|[.!?;:\n])(?:(?!\b(?:no|not|nothing|never|once|after|when|later|will|would|then)\b|n''t\b|''ll\b)[^.!?;:\n])*?\b(?:claim(?:ed|ing)?|working|picking up|pick up)\b[^.!?;:\n]{0,30}?(?:#\d+|\bitem\b)'
flags: i
---
