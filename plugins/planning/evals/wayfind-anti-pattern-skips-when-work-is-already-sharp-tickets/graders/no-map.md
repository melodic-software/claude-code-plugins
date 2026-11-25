---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?add\b[^\n]*(?:--parent\b|(?:wayfind:|<prefix>) (?:map|research|interview|design|prototype|task)\b)|(?:^|\n)[#>*\s-]*Map:\**[ \t]+(?!(?:[Nn]one|[Nn]o|[Nn]ot|n/a)\b)\S|Not-yet-specified\**[ \t]*:?\**[ \t]*(?:\n[ \t]*)*(?:[-*][ \t]+)?\*\*[^*\n]{1,60}\*\*|\b[Dd]ecision items?:\**[ \t]*(?:\n[ \t]*(?:[-*]|\d+\.)[ \t]*)?["''‘“*]|(?:^|[.!?;:\n])(?:(?!\b(?:[Nn]o|[Nn]ot|[Nn]ever|[Ww]ould|[Cc]ould|[Ii]nstead|[Rr]ather|[Ss]kip(?:ping)?|[Nn]othing|[Ww]ithout|[Uu]nless|[Ii]f|[Ww]hether)\b|n''t\b)[^.!?;:\n])*?\b(?:[Cc]reat(?:e|ed|ing)|[Oo]pen(?:ed|ing)|[Ff]il(?:ed|ing)|[Cc]hart(?:ed|ing)?|[Bb]uil(?:t|ding)|[Dd]raft(?:ed|ing))\b(?:(?!\b(?:[Nn]o|[Nn]ot)\b|n''t\b)[^.!?;:\n]){0,40}?\b(?:[Mm]ap|[Dd]ecision items?)\b(?![^.!?;:\n]{0,12}\b(?:would|could|is not|isn''t)\b)'
---
