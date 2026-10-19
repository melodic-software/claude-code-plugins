---
type: regex
pattern: 'human[- ]decision[\s\S]{0,200}?(?<!non-)(?<!non )\bblock(?:ing|er)\b|(?<!non-)(?<!non )\bblock(?:ing|er)\b[\s\S]{0,200}?human[- ]decision'
flags: 'i'
target: last_message
---
