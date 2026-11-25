---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:add|edit|link|start|done|publish-plan)\b|\b[Cc]reated:?\s+(?:the |decision |map )*(?:item|issue|map)?\s*["''‘“]|(?:^|[.!?;:,\n])(?:(?!\b(?:[Nn]o|[Nn]ot|[Nn]ever|[Ww]ould|[Cc]ould|[Ww]ill|[Ss]hall|[Ss]hould|[Cc]an|[Oo]nce|[Aa]fter|[Ww]hen|[Bb]efore|[Ii]f|[Ww]hether|[Nn]othing|[Uu]ntil)\b|n''t\b|''ll\b)[^.!?;:,\n])*?\b(?:[Cc]reated|[Oo]pened|[Ff]iled)\b(?:(?!\b(?:[Nn]o|[Nn]ot|[Ww]ould|[Cc]ould|[Ww]ill|[Uu]ntil)\b|n''t\b)[^.!?;:,\n]){0,40}?\b(?:[Mm]ap|[Dd]ecision items?|[Ii]tems?|issues?)\b'
---
