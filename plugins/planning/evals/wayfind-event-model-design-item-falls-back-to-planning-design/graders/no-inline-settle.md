---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:(?:Arg|arg)(?:ument)?s[\s:=*`"]*)?(?:done|close)\s+(?:<?(?:item|issue)\s+)?\S*?\b903\b|work-items:track[\s`*"]*(?:(?:Arg|arg)(?:ument)?s[\s:=*`"]*)?(?:edit|comment)\s+(?:<?(?:item|issue)\s+)?\S*?\b903\b[^\n]*--comment|(?:^|\n)[ \t>*`#-]*(?:\d+[.)]\s*)?\**Resol(?:ved|ution)\**:\**(?![ \t*]*(?:pending|none|not yet|tbd|after|once|comes)\b)|(?:^|[.!;:\n]\s*)(?:(?:I am|I''m|Now|and)\s+)?(?:Closing|closing)\s+(?:item\s+|issue\s+)?#?903\b(?![^\n.]{0,40}\b(?:after|once|when|later|waits)\b)|\b(?:Post|post)(?:ing|ed)\b[^\n.]{0,40}\bresolution\b(?![^\n.]{0,40}\b(?:after|once|when|later)\b)'
---
