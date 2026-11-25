---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:add|edit|link|start|done|publish-plan)\b|(?:^|\n)[#>*\s-]*Map:\**[ \t]+(?!(?:[Nn]one|[Nn]o|[Nn]ot|n/a)\b)\S|Not-yet-specified\**[ \t]*:?\**[ \t]*(?:\n[ \t]*)*(?:[-*][ \t]+)?\*\*[^*\n]{1,60}\*\*|\b(?:[Dd]ecision )?[Ii]tems?:\**[ \t]*(?:\n[ \t]*(?:[-*]|\d+\.)[ \t]*)?["''‘“*]|\b[Cc]reated:?\s+(?:the |decision |map )*(?:item|issue|map)?\s*["''‘“]'
---
