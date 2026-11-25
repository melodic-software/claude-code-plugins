---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:done|close)\s+(?:<?(?:item|issue)\s+)?\S*?\b903\b|work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:edit|comment)\s+(?:<?(?:item|issue)\s+)?\S*?\b903\b[^\n]*--comment|(?:^|\n)[ \t>*`#-]*(?:\d+[.)]\s*)?\**Resolved\**:'
---
