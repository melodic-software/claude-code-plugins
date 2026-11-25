---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:done|close)\s+(?:<?(?:item|issue)\s+)?\S*?\b903\b|work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:edit|comment)\s+(?:<?(?:item|issue)\s+)?\S*?\b903\b[^\n]*--comment|(?:^|\n)[ \t>*`#-]*(?:\d+[.)]\s*)?\**Resol(?:ved|ution)\**:\**(?![ \t*]*(?:pending|none|not yet|tbd|after|once|comes)\b)|(?:^|[.!;:\n]\s*)(?:(?:I am|I''m|Now|and)\s+)?[Cc]losing\s+(?:item\s+|issue\s+)?#?903\b(?![^\n.]{0,40}\b(?:after|once|when|later|waits)\b)|\b[Pp]ost(?:ing|ed)\b[^\n.]{0,40}\bresolution\b(?![^\n.]{0,40}\b(?:after|once|when|later)\b)'
---
