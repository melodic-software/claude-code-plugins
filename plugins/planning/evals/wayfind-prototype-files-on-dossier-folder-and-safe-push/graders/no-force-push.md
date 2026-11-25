---
type: regex
match: not_contains
pattern: '(?<!never )(?<!not )(?<!no )(?<!without )(?<!never `)(?<!without `)\bgit push\b[^\n`]*?\s(?<!\bno\s)(?<!\bnot\s)(?<!\bnever\s)(?<!\bwithout\s)(?:--force|-f\b|\+[\w./-])'
flags: i
---
