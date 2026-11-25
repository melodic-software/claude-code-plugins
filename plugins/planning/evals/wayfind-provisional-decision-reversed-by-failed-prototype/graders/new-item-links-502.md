---
type: regex
pattern: '(?:work-items:track[\s`*"]*(?:(?:Arg|arg)(?:ument)?s[\s:=*`"]*)?add\b|(?<!no )(?<!not )(?<!n''t )(?<!without )\b(?:create|open)(?:s|ing|ed)?\b|(?<!no )(?<!not a )(?<!without a )\bnew (?:decision )?item\b)(?:(?!work-items:track[\s`*"]*(?:done|edit)\b)[\s\S]){0,800}?(?:\[Pick the vendor\]\(|\b(?:link\w*|supersede\w*|superseding\w*|replac\w*|refs?:?|revisit\w*|re-?(?:decide|deciding|decision)\w*)\b[^\n]{0,60}?(?:\[?Pick the vendor\]?|#502\b|issues/502\b))'
flags: i
---
