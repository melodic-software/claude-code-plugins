---
type: regex
pattern: '\bif\b[^\n]{1,160}\b(then|will|would|should)\b|(?:^|\n)[ \t]*\|(?:[^|\n]*\|)*?[^|\n]*\b(?:if|predict\w*)\b[^|\n]*\|[^\n]*\n[ \t]*\|[ \t:|-]*\n[ \t]*\|(?:(?![ \t*_]*(?:tbd|todo|n/?a|none)[ \t*_]*\|)[^|\n]*[a-z0-9][^|\n]*\|)+[ \t]*(?:\n|$)'
flags: i
---
