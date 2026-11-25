---
type: regex
match: not_contains
flags: i
pattern: '(?:^|[.!?;\n]\s*)(?:(?!\b(?:not|never|nothing|no|none|only|stay|stays|remain|remains|keep|keeps|leave|leaves)\b|n''t\b)[^.!?;\n])*?\b(?:mov\w*|transferr?\w*|shift\w*|relocat\w*|put|puts|add|adds|added|adding)\b[^.!?;\n]{0,120}?(?:Not-yet-specified|\bfog\b)[^.!;\n]{0,120}?Out-of-scope|Out-of-scope[^.!?;\n]{0,60}\b(?:gets|now (?:holds|includes|lists))\b[^.!?;\n]{0,60}\bfog\b'
---
