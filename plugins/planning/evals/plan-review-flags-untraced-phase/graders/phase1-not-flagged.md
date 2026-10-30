---
type: regex
pattern: '^(?![^\n]*(?:\bPhase\s*2\b|\bcach\w*))(?=[^\n]*\bPhase\s*1\b)[^\n]*(?:\buntraced\b|\bserves?\s+(?:no|neither)\s+(?:\w+\s+){0,1}criteri(?:on|a)\b|\bdo(?:es)?(?:n''t| not)\s+(?:trace|map)\s+to\s+(?:a|an|any)\s+(?:acceptance\s+)?criteri(?:on|a)\b)'
flags: mi
match: not_contains
target: last_message
---
