---
type: regex
pattern: '\bAC2\b(?:(?!\bAC\d|\.\s)[^\n]){0,160}?(?<!\bnot\s)(?<!n''t\s)(?<!\bnothing\s)(?<!\bnone\s)\b(already\s+(passes|passing|passed|pass|met|holds|exits\s+0)|pass(es|ing)\s+(at|on)\s+(the\s+)?base)|\balready\s+pass\w*(?:(?!\bAC\d|\.\s)[^\n]){0,40}?\bAC2\b'
flags: i
---
