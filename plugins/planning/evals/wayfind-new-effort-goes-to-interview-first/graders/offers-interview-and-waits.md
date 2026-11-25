---
type: regex
pattern: '^(?![\s\S]*?(?:^|\n|[.!:]\s+)[*_`]*(?:Starting|Running|Invoking|Launching|Opening)\b[^\n?]{0,40}\binterview\b(?![^\n]{0,60}\?))(?=[\s\S]*?(?:^|[.!?;,\n—–]\s*)(?:(?!\b(?:not|never|skip|instead of|rather than|unless)\b|n''t\b|\bno need\b)[^.!?;,\n—–])*?/?planning:interview\b)[\s\S]*(?:\?|\bwait(?:ing)?\b[^\n]*|\b(?:yes or no|your answer|let me know)\b[^\n]*)[\s*_`)\].]*$'
flags: i
---
