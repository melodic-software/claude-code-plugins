---
type: regex
pattern: '\b(?:Notes?|standing preference)\b(?:(?!\n[ \t]*\n)[\s\S]){0,250}?(?:\b(?:cannot|can''t|can ?not|does not|doesn''t|do not|don''t|never|won''t|will not|nothing can)\s+(?:\w+\s+){0,3}?(?:override|overrule|carry|bring|authori[sz]e|unlock)\w*|\bplan,? don(?:''|’)?t do\b)|\b(?:plan,? don(?:''|’)?t do|no)\b[^\n]{0,250}?\b(?:Notes?|standing preference)\b[^\n]{0,80}\boverrid|\b(?:cannot|can''t|can ?not|does not|doesn''t|never|won''t|nothing can)\s+(?:\w+\s+){0,3}?overrid\w*\b[^\n]{0,40}\b(?:Notes?|standing preference)\b'
flags: i
---
