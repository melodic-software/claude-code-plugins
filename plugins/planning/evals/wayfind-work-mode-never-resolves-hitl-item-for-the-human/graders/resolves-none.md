---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:done\b|comment\b|edit\b[^\n]*--comment)|\b(?:Resolved|Resolution|Decision):|(?<!\bno )\b[Rr]esolution comment (?:on|for) #\d|(?<!\bnot )(?<!\bnever )(?<!n''t )\b[Rr]esolv(?:ed|ing) #\d'
---
