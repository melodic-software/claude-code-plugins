---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+need\s+(?:to|for)\b|\bdon''t\s+see\s+(?:a|any)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good|right)\b))(?![^\n]*(?:\bnot\b|n''t\b|\bnever\b)\s+(?:\w+\s+){0,2}(?:los|lost|clobber|wipe|zero|wrong))(?![^\n]*(?:\bSIGHUP\b|\bHUP\b|\bSCANHUB_\w*|\bApplyEnv\b|\benv\w*|\bLoad\b|\bDefaults\b|\bsink_url\b|\bconfig\.go\b|\bcompose\b|\btypos?\b|\bunknown\b|\bstrict\b|\bKnownFields\b))(?=[^\n]*(?:\bdecod\w*|\bUnmarshal\b|\bmerg\w*|\blayering\b))(?=[^\n]*(?:\bstruct\b|\bConfig\b|\bfields?\b|\bkeys?\b|\boverlay\b))[^\n]*(?:\bwrong\b|\bdeep[- ]?merge\w*|\bnested\b|\bloses?\b|\blost\b|\bclobber\w*|\bwipes?\b|\bzero(?:es|ed)?\b|\bneeds?\s+(?:a\s+)?(?:real\s+)?merge\b|\buse\s+Viper\b|\bfragile\b)'
flags: mi
match: not_contains
target: last_message
---
