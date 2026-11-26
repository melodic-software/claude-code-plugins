---
type: regex
match: not_contains
pattern: '(?:^|[.!?;\n])(?:(?!\b(?:not|never|no|skip|without|instead of|rather than|unless|nor|already)\b|n''t\b)[^.!?;\n])*?(?:\b(?:run|start|invoke|offer|route|go(?:ing)? (?:back )?to|begin|hand(?:ing)? (?:it )?(?:off|over) to|switch(?:ing)? to|recommend|suggest|try)\b[^.!?;\n]{0,40}?/?planning:(?:interview|plan)\b(?![- ](?:round|panel))|\bSkill:[\s`*"]*/?planning:(?:interview|plan)\b|\binterview(?:ing)? (?:you |it |this |the (?:effort|overhaul) )?(?:first|again)\b|\b(?:re-?run|restart|redo|resume) (?:the |an )?interview\b|\b(?:another|one more|a fresh|a new|a second) (?:/?planning:)?interview\b)'
flags: i
---
