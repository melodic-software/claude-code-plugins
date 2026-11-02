---
type: regex
pattern: 'C2-auto-merge(?:(?!\bnot\b|n''t\b|\bnever\b|\bno\b|C[0-9]-)[^\n]){0,200}?(?:\bunpromoted\b|\bdemot(?:ed|ion|es)\b|\bit(?:\s+is|''s)\s+(?:now\s+)?off\b)|C2-auto-merge(?:(?:\s+is|''s)\s+(?:now\s+)?off\b|(?:\s+(?:has\s+been|was|is))?\s+lowered\b)|(?<!not )(?<!never )(?<!n''t )\bdemoted\b(?:(?!\bnot\b|n''t\b|\bnever\b|\bno\b)[^\n:]){0,40}:(?:(?!\bnot\b|n''t\b|\bnever\b|\bno\b)[^\n]){0,200}?C2-auto-merge'
flags: i
---
