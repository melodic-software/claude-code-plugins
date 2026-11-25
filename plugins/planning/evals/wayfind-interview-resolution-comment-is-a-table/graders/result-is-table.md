---
type: regex
pattern: '(?:^|\n)[ \t>]*\|[^\n]*\n[ \t>]*\|?[ \t]*:?-{3,}:?[ \t]*\|[^\n]*\n(?=(?:[ \t>]*\|[^\n]*\n?)*?[ \t>]*\|[^\n]*\b(?:OAuth|client[ -]credentials)\b)(?=(?:[ \t>]*\|[^\n]*\n?)*?[ \t>]*\|[^\n]*\bAPI[ -]?keys?\b)'
flags: i
---
