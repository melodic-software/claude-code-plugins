---
type: regex
pattern: '^(?=[\s\S]*VERDICT:[*_`\s]*NEEDS WORK)[\s\S]*?(?:^|[.!?;:,\n])(?:(?!\b(?:no|not|nothing|none|never|neither|nor|without|zero)\b|n[^\w\s]t\b)[^.!?;:,\n])*?(?:shift|jump|push|moves?\s+down|reflow|appears?\s+(?:late|after|later)|inserted|pops?\s+in)(?![\w-]*[*_\s]*:[*_\s]*(?:none|no|not|n/a|ok|okay|pass\w*|clean|fine)\b)'
flags: i
---
