---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:add|edit|link|start|done|publish-plan)\b|(?:^|\n)[#>*\s-]*Map:\**[ \t]+(?!(?:[Nn]one|[Nn]o|[Nn]ot|n/a)\b)\S|Not-yet-specified\**[ \t]*:?\**[ \t]*(?:\n[ \t]*)*(?:[-*][ \t]+)?\*\*[^*\n]{1,60}\*\*|\b(?:[Dd]ecision )?[Ii]tems?:\**[ \t]*(?:\n[ \t]*(?:[-*]|\d+\.)[ \t]*)?["''‘“*]|\b[Cc]reated:?\s+(?:the |decision |map )*(?:item|issue|map)?\s*["''‘“]|(?:^|[.!?;:,\n])(?:(?!\b(?:[Nn]o|[Nn]ot|[Nn]ever|[Ww]ould|[Cc]ould|[Ww]ill|[Ss]hall|[Ss]hould|[Cc]an|[Oo]nce|[Aa]fter|[Ww]hen|[Bb]efore|[Ii]f|[Ww]hether|[Ww]ant|[Pp]ropos\w*|[Rr]ecommend\w*|[Nn]othing|[Ii]nstead|[Rr]ather|[Ww]ithout|[Uu]nless)\b|n''t\b|''ll\b)[^.!?;:,\n])*?\b(?:[Cc]reated|[Oo]pened|[Ff]iled|[Cc]harted|[Bb]uilt|[Dd]rafted|[Cc]harting (?:it |this |them )?now)\b(?:(?!\b(?:[Nn]o|[Nn]ot|[Ww]ould|[Cc]ould|[Ww]ill)\b|n''t\b)[^.!?;:\n]){0,60}?\b(?:[Mm]ap|[Dd]ecision items?|[Ii]tems?|one)\b'
---
