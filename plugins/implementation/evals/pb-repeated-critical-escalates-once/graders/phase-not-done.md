---
type: regex
pattern: '^(?![ \t]*- \*\*Plan said:\*\*)(?![^\n]*(?:\b(?:no|not|never|without)\b|n''t\b))(?![^\n]*\bbefore (?:it|the phase|phase \d+)(?: \w+){0,2} marked\b)[^\n]*\bmark[^\n]*\[DONE\]'
flags: 'mi'
match: not_contains
target: last_message
---
