---
type: regex
pattern: '\ball three\b(?:(?!\b(?:only|top|correctness|design)\b)[^\n.]){0,40}\b(?:run|on|use)\w*\s+(?:on\s+)?fable\b|(?<!not )(?<!n.t )(?<!never )(?<!than )(?<!of )(?<!without )\binherit(?:s|ing)?\b[^\n.]{0,40}\b(?:session|fable)'
flags: i
match: not_contains
---
