---
type: regex
match: not_contains
pattern: '(?:checkout\s+-b\s+|switch\s+-c\s+|\bbranch[,:]?\s+(?:-[a-z]\s+)?|\bpush\s+(?:-u\s+)?[\w-]+\s+)[`''"]?(?!dossier/)[\w./-]*504|(?:^|[.!?;,\n])(?:(?!\b(?:no|not|never|without)\b|n''t\b)[^.!?;,\n])*?\bnew (?:per-item )?branch\b[^\n]{0,60}?#?504\b'
flags: i
---
