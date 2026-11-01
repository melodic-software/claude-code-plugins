---
type: regex
pattern: "````(?:markdown|md)[ \\t]*\\n(?:(?!````)[\\s\\S])*(?:actions/checkout|deflake|ledger/(?:io|mod)\\.rs|serde|\\btypo\\b)"
flags: "i"
match: not_contains
arm: both
---
