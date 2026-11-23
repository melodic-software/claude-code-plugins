---
type: regex
pattern: '^\W*Asking here\b[^\n]*\.[^\S\n]+[^\n]*\balso available\b[^\n]*$'
flags: mi
match: "count:1"
target: last_message
arm: with-only
---
