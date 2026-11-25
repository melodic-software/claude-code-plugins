---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?add\b[^\n]*(?:--parent\b|(?:wayfind:|<prefix>) (?:map|research|interview|design|prototype|task)\b)|(?:^|\n)[#>*\s-]*Map:\**[ \t]+(?!(?:[Nn]one|[Nn]o|[Nn]ot|n/a)\b)\S|Not-yet-specified\**[ \t]*:?\**[ \t]*(?:\n[ \t]*)*(?:[-*][ \t]+)?\*\*[^*\n]{1,60}\*\*|\b[Dd]ecision items?:\**[ \t]*(?:\n[ \t]*(?:[-*]|\d+\.)[ \t]*)?["''‘“*]'
---
