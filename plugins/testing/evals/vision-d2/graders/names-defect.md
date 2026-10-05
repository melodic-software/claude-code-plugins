---
type: regex
pattern: '^(?=[\s\S]*VERDICT:[*_`\s]*NEEDS WORK)[\s\S]*?(?:^|[.!?;:,\n])(?:(?!\b(?:no|not|nothing|none|never|neither|nor|without|zero)\b|n[^\w\s]t\b)[^.!?;:,\n])*?(?:clip|truncat|cut[ -]?off|cropped|overflow)(?![\w-]*[*_\s]*:[*_\s]*(?:none|no|not|n/a|ok|okay|pass\w*|clean|fine)\b)'
flags: i
---
