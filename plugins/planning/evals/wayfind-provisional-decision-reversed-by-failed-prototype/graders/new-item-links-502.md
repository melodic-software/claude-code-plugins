---
type: regex
pattern: '(?:work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?add\b|\b(?:create|open)(?:s|ing|ed)?\b|\bnew (?:decision )?item\b)(?:(?!work-items:track[\s`*"]*(?:done|edit)\b)[\s\S]){0,800}?(?:\[Pick the vendor\]\(|\b(?:link\w*|supersed\w*|replac\w*|refs?:?|revisit\w*|re-?decid\w*)\b[^\n]{0,60}?(?:\[?Pick the vendor\]?|#502\b|issues/502\b))'
flags: i
---
