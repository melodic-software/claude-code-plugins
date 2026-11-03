---
type: regex
pattern: '(?:deriv|generat)\w*[\s\S]{0,200}?(?:\bmigrations?\b|\.sql\b)|(?:\bmigrations?\b|\.sql\b)[\s\S]{0,200}?(?:deriv|generat)\w*'
flags: i
target: { source: file, path: .work/deploy-records/design/type-inventory.md }
---
