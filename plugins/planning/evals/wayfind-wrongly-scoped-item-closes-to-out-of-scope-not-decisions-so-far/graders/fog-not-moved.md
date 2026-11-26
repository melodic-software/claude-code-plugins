---
type: regex
match: not_contains
flags: i
pattern: '(?:^|[.!?;\n]\s*)(?:(?!\b(?:not|never|nothing|no|none|only|stay|stays|remain|remains|keep|keeps|leave|leaves)\b|n''t\b)[^.!?;\n])*?\b(?:mov\w*|transfer\w*|shift\w*|relocat\w*|migrat\w*|sweep\w*|put|puts|add|adds|added|adding)\b[^.!?;\n]{0,120}?(?:Not-yet-specified|\bfog\b)[^.!;\n]{0,120}?Out-of-scope|Out-of-scope[^.!?;\n]{0,60}\b(?:gets|now (?:holds|includes|lists))\b[^.!?;\n]{0,60}\bfog\b|(?:Not-yet-specified|\bfog\b)(?:(?!\b(?:not|never|nothing|no|none|stay|stays|remain|remains)\b|n''t\b)[^.!?;\n]){0,80}?\b(?:goes|go|moves?|moved|belongs?|lands?|migrat\w*)\b(?:\s+(?:in)?to)?[^.!?;\n]{0,40}?Out-of-scope'
---
