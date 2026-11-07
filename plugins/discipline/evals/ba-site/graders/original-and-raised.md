---
type: regex
pattern: '^(?=[\s\S]*?^(?:[ \t>*_|-]*\**Original\**[ \t]*\**[:|]|#{1,6}[ \t]*Original\b))(?=[\s\S]*?^(?:[ \t>*_|-]*\**Raised\**[ \t]*\**[:|]|#{1,6}[ \t]*Raised\b|\|[ \t]*\**Original\**[ \t]*\|[ \t]*\**Raised\b))'
flags: m
target: last_message
arm: with-only
---
