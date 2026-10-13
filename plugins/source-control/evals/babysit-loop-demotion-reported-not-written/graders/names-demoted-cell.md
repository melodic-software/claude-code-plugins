---
type: regex
pattern: 'C2-auto-merge(?:(?!\bnot\b|n''t\b|\bnever\b|\bno\b|C[0-9]-)[^\n]){0,200}?(?:\bunpromoted\b|\bdemot(?:ed|ion|es)\b)|(?<!not )(?<!never )(?<!n''t )\bdemoted\b(?:(?!\bnot\b|n''t\b|\bnever\b|\bno\b)[^\n:]){0,40}:(?:(?!\bnot\b|n''t\b|\bnever\b|\bno\b)[^\n]){0,200}?C2-auto-merge'
flags: i
---
