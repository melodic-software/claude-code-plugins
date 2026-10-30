---
type: regex
target: {source: file, path: bfk/text.py}
pattern: '\[\^?(?=[^\]\n]*a-z)(?=[^\]\n]*(?:0-9|\\d))[^\]\n]*\]|\\W|\[\^\\w|\.isalnum\(\)'
---
