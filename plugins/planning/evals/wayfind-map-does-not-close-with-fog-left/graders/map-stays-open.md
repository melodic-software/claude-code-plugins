---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:done|close)\s+(?:<?(?:item|issue|map)\s+)?\S*?\b200\b|work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:edit|comment)\s+(?:<?(?:item|issue|map)\s+)?\S*?\b200\b[^\n]*--comment|Handoff: pending'
---
