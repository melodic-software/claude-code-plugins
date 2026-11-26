---
type: regex
match: not_contains
pattern: '(?:^|\n)[ \t>*`-]*Skill(?: call)?\**[ \t]*:[ \t*`"]*/?event-storming:|"skill"\s*:\s*"/?event-storming:|(?:^|[.!?;,\n])(?:(?!\b(?:not|never|cannot|without|unless|instead of|rather than|would|could|might|normally|usually|ordinarily|otherwise)\b|n''t\b|''d\b)[^.!?;,\n])*?\b(?:invok(?:e|ing)|call(?:ing)?|rout(?:e|ing)\s+(?:#?903\s+|it\s+|the item\s+)?to|hand(?:ing)?\s+(?:#?903\s+|it\s+|the item\s+)?(?:off\s+|over\s+)?to)[\s:*`"]*/?event-storming:'
flags: i
---
