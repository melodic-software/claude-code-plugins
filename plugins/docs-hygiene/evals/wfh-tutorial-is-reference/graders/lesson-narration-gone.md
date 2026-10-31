---
type: regex
pattern: "````(?:markdown|md)[ \\t]*\\n(?:(?!````)[\\s\\S])*(?:\\bwe will\\b|\\bwe.ll\\b|\\blet.s\\b|great job|take your time|\\bwelcome\\b)"
flags: "i"
match: not_contains
arm: both
---
