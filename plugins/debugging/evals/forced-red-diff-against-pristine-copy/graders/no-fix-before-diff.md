---
type: regex
target: trace
match: not_contains
pattern: '^(?:(?!\\?"name\\?":\s*\\?"Bash\\?",\s*\\?"input\\?":\s*\{\s*\\?"command\\?":\s*\\?"(?:[^"\\]|\\.)*?(?:(?:(?<=\\n)|(?<=\\t)|(?<![\w\\-]))git\s+(?:-C\s+\S+\s+)?(?:--no-pager\s+)?(?:diff\b|show\s+(?:HEAD|[0-9a-f]{6,})(?:[~^]\d*)?:)|(?:(?<=\\n)|(?<=\\t)|(?<![\w\\-]))(?:diff|cmp)\s))[\s\S])*?(?:\\?"name\\?":\s*\\?"(?:Edit|Write|MultiEdit)\\?",\s*\\?"input\\?":\s*\{[^}]{0,300}?orders/pricing\.py|\\?"name\\?":\s*\\?"Bash\\?",\s*\\?"input\\?":\s*\{\s*\\?"command\\?":\s*\\?"(?:[^"\\]|\\.)*?(?:(?:(?<=\\n)|(?<=\\t)|(?<![\w\\]))(?:sed|perl)\s+(?:(?:[^"\\|;&]|\\[^n])*?\s)?-[a-zA-Z]*i(?:[^"\\|;&]|\\[^n])*?pricing\.py|>>?\|?\s*(?:\\")?(?:[^\s"\\;&|]*/)?pricing\.py))'
---
