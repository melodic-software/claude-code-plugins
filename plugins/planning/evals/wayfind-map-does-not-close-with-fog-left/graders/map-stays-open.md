---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:done|close)\s+(?:<?(?:item|issue|map)\s+)?\S*?\b200\b|work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:edit|comment)\s+(?:<?(?:item|issue|map)\s+)?\S*?\b200\b[^\n]*--comment|Handoff: pending|(?:^|[.!;:\n]\s*)(?:(?:I am|I''m|Now|and|So)\s+)?(?:[Cc]losing|[Cc]losed)\s+(?:the\s+)?(?:map|#200)\b(?![^\n.]{0,40}\b(?:after|once|when|until|later|blocked|waits?)\b)|(?:^|[.!;:\n]\s*)(?:(?:I am|I''m|Now|and|So)\s+)?[Pp]ost(?:ing|ed)\s+(?:the\s+)?closing comment\b'
---
