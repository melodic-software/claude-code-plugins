---
type: regex
pattern: "```(?:markdown|md)\\n(?:(?!```)[\\s\\S])*(?:chmod|chown|sudo|fix (?:the )?(?:file )?permissions)"
flags: i
match: not_contains
arm: both
---
