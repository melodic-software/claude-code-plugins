---
type: regex
pattern: "````(?:markdown|md)[ \\t]*\\n(?:(?!````)[\\s\\S])*(?:(?:\\bedit|\\bchang|\\bmerged\\b|\\binstead\\b|\\brather than\\b)[^\\n]*\\b(?:new|another|separate|follow-up|fresh)\\b[^\\n]{0,20}\\bmigration|\\b(?:new|another|separate|follow-up|fresh)\\b[^\\n]{0,20}\\bmigration[^\\n]*(?:\\bedit|\\bchang|\\bmerged\\b|\\binstead\\b|\\brather than\\b))"
flags: "i"
arm: both
---
