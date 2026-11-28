---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:args?(?:uments?)?[\s:=*`"]*)?(?:done|close)\s+(?:<?(?:item|issue|map)\s+)?\S*?\b200\b|work-items:track[\s`*"]*(?:args?(?:uments?)?[\s:=*`"]*)?(?:edit|comment)\s+(?:<?(?:item|issue|map)\s+)?\S*?\b200\b[^\n]*--comment|Handoff: pending|(?:^|[.!;:\n]\s*)(?:(?:I am|I''m|I''ve|I have|I|Now|and|So)\s+)?(?:closing|closed)\s+(?:the\s+)?(?:map|#200)\b(?![^\n.]{0,40}\b(?:after|once|when|until|later|blocked|waits?)\b)|(?:\bmap\b(?:\s+#?200\b)?|#200\b)(?:\s+(?:is|was|has been|been|now|already))*\s+closed\b(?![^\n.]{0,40}\b(?:after|once|when|until|later|blocked|waits?)\b)|(?:^|[.!;:\n]\s*)(?:(?:I am|I''m|Now|and|So)\s+)?post(?:ing|ed)\s+(?:the\s+)?closing comment\b'
flags: i
---
