---
type: regex
pattern: '^(?![^\n]*No plan gaps found)(?![^\n]*\b(?:no\s+need\s+to|not|never|without|should\s+not|will\s+not)\s+(?:be\s+)?(?:cut|drop\w*|remov\w*|flag\w*)\b)(?![^\n]*\bno\s+(?:cut|drop|removal|flag|finding|issue|concern)s?\b)(?![^\n]*n''t\s+(?:need\s+to\s+|have\s+to\s+|see\s+(?:a|any)\s+reason\s+to\s+)?(?:be\s+)?(?:cut|drop\w*|remov\w*|flag\w*)\b)(?=[^\n]*(?:\bPhase\s*2\b|\b(?:cache\w*|caching)))[^\n]*(?:\b(?:serves?|serving|maps?|traces?|tied|linked)\s+(?:back\s+)?(?:to\s+)?(?:no|neither|none of)\b|\b(?:no|neither)\s+(?:\w+\s+){0,2}(?:acceptance\s+)?criteri(?:on|a)\b|\bnot\s+(?:\w+\s+){0,3}(?:any|either)\s+(?:\w+\s+){0,2}criteri(?:on|a)\b|\b(?:untraced|unrequested|untraceable)\b|\bdo(?:es)?(?:n''t| not)\s+(?:trace|map|serve|tie)\b|\bOpen Decision\b|\bcut\b|\bscope creep\b|\b(?:drop|remove)\s+(?:it|phase\s*2|the\s+(?:\w+\s+)?(?:cache\w*|caching))\b)'
flags: mi
target: last_message
---
