---
type: regex
pattern: '^(?![^\n]*\b(?:no|not|never|without|skip\w*|won[''’]t|don[''’]t|isn[''’]t|needn[''’]t|nothing|none|unnecessary|n/a)\b(?![ \t]+(?:available|installed|loaded|reachable)\b))(?:(?=[^\n]*\bone-way\b)[^\n]*|[^\n]*\bone-way\b[^\n]*\n(?:[^\n]*\n){0,5}?(?![^\n]*\b(?:no|not|never|without|skip\w*|won[''’]t|don[''’]t|isn[''’]t|needn[''’]t|nothing|none|unnecessary|n/a)\b(?![ \t]+(?:available|installed|loaded|reachable)\b))[^\n]*)(?:architecture:record-decision|\b(?:record|write|draft|offer|recommend|prompt|run|need|requir)\w*\b[^\n]*?\b(?:ADR|architecture decision record)\b|\b(?:ADR|architecture decision record)\b[^\n]*?\b(?:offer|recommend|record|write|draft|prompt)\w*\b)'
flags: mi
---
