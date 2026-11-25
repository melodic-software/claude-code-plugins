---
type: regex
match: not_contains
pattern: '(?<!never )(?<!not )(?<!no )(?<!without )(?<!never `)(?<!without `)\bgit push\b[^\n`]*?\s(?<!\bno\s)(?<!\bnot\s)(?<!\bnever\s)(?<!\bwithout\s)(?:--force|-f\b|\+[\w./-])|(?:^|\n)(?:(?!\b(?:no|not|never|without)\b|n''t\b)[^\n])*?\bforce[- ]?push'
flags: i
---
