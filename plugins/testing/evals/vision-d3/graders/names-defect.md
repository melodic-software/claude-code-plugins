---
type: regex
pattern: '(?<![\s\S])(?=[\s\S]*VERDICT:[*_`\s]*NEEDS WORK)[\s\S]*?^[ \t]*(?:(?:[-*+>]|\d+[.)])[ \t]+)?[*_`]*FINDING[*_`]*:[*_`]*(?:[^\n]*?[.!?;:,])??(?:(?!\b(?:no|not|nothing|none|never|neither|nor|without|zero)\b|n[^\w\s]t\b)[^.!?;:,\n])*?(?:(?:\b(?:low|lower|poor|insufficient|weak|fail\w*|faint|pale|washed[ -]out|hard to read|too light|below|under))\b(?:(?!\b(?:no|not|nothing|none|never|neither|nor|without|zero)\b|n[^\w\s]t\b|\.(?!\d))[^!?;\n]){0,60}?contrast|contrast(?:(?!\b(?:no|not|nothing|none|never|neither|nor|without|zero)\b|n[^\w\s]t\b|\.(?!\d))[^!?;\n]){0,60}?\b(?:low|lower|poor|insufficient|weak|fail\w*|too light|below|under)\b)(?![\w-]*[*_\s]*:[*_\s]*(?:none|no|not|n/a|ok|okay|pass\w*|clean|fine)\b)'
flags: im
---
