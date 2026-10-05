---
type: regex
pattern: '^(?=[\s\S]*VERDICT:[*_`\s]*NEEDS WORK)[\s\S]*?(?:^|[.!?;:,\n])(?:(?!\b(?:no|not|nothing|none|never|neither|nor|without|zero)\b|n[^\w\s]t\b)[^.!?;:,\n])*?(?:(?<![\d.,])(?:5|five)\b(?![.,]\d)[^\n]{0,120}?(?:only\s+(?:4|four)\b|(?<![\d.,])(?:4|four)\s+(?:\w+\s+){0,2}?(?:items?|rows?|entries|products|results|bullets?|listed|shown|render\w*|visible|appear\w*|lines?)\b)|(?:only\s+(?:4|four)\b|(?<![\d.,])(?:4|four)\s+(?:\w+\s+){0,2}?(?:items?|rows?|entries|products|results|bullets?|listed|shown|render\w*|visible|appear\w*|lines?)\b)[^\n]{0,120}?(?<![\d.,])(?:5|five)\b(?![.,]\d))(?![\w-]*[*_\s]*:[*_\s]*(?:none|no|not|n/a|ok|okay|pass\w*|clean|fine)\b)'
flags: i
---
