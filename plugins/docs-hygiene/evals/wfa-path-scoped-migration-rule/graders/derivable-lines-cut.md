---
type: regex
pattern: "````(?:markdown|md)[ \\t]*\\n(?:(?!````)[\\s\\S])*(?:well-formatted SQL|be careful with migrations|start with a timestamp|plain SQL files|\\.down\\.sql)"
flags: "i"
match: not_contains
arm: both
---
