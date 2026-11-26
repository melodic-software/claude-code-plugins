---
type: regex
match: not_contains
pattern: '(?:^|[.!?;\n]|:(?=\s))(?:(?!\b(?:not|never|no|skip|without|instead of|rather than|unless|nor)\b|n''t\b)(?:[^.!?;:\n]|:(?!\s)))*?(?:/?planning:interview\b|\binterview(?:ing)? (?:you |it |this |the (?:flow|effort|work) )?first\b|\brun (?:an|the|a quick) interview\b|\binterview\b(?:(?!\b(?:not|no|never)\b|n''t\b)[^.!?;\n]){0,60}\b(?:before|beforehand|ahead of)\b|\bbefore\b(?:(?!\b(?:not|no|never)\b|n''t\b)[^.!?;\n]){0,60}\binterview)'
flags: i
---
