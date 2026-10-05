---
type: regex
pattern: '(?<![\s\S])(?=[\s\S]*VERDICT:[*_`\s]*NEEDS WORK)[\s\S]*?^[ \t]*(?:(?:[-*+>]|\d+[.)])[ \t]+)?[*_`]*FINDING[*_`]*:[*_`]*(?:[^\n]*?[.!?;:,])??(?:(?!\b(?:no|not|nothing|none|never|neither|nor|without|zero)\b|n[^\w\s]t\b)[^.!?;:,\n])*?(?:misalign\w*|out of (?:alignment|line)|not (?:\w+\s+)?(?:aligned|level|lined up|flush)|unaligned|offset|(?:lower|higher) than|sits? (?:\w+\s+){0,3}?(?:lower|higher)|uneven|stagger\w*|top edges? (?:differ|do not|don\Wt))(?![\w-]*[*_\s]*:[*_\s]*(?:none|no|not|n/a|ok|okay|pass\w*|clean|fine)\b)'
flags: im
---
