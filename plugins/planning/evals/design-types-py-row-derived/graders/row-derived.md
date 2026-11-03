---
type: regex
pattern: '(?:deriv\w*|generate\w*|generating|generation)[\s\S]{0,200}?(?:\bmigrations?\b|\.sql\b)|(?:\bmigrations?\b|\.sql\b)[\s\S]{0,200}?(?:deriv\w*|generate\w*|generating|generation)'
flags: i
target: { source: file, path: .work/deploy-records/design/type-inventory.md }
---
