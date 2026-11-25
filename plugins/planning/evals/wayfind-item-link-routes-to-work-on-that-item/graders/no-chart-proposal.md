---
type: regex
match: not_contains
pattern: 'planning:wayfind\s+chart\b|\b(?:shall|should|may|can) I (?:chart|start (?:a (?:new )?map|charting))\b|\bwant me to (?:chart|start (?:a (?:new )?map|charting))\b|(?<!\bnot )(?<!\bno )(?<!\bnever )(?<!n''t )\bpropos(?:e|ing)\s+(?:to\s+)?chart(?:ing)?\b|work-items:track[^\n]*\badd\b[^\n]*wayfind: map'
flags: i
---
