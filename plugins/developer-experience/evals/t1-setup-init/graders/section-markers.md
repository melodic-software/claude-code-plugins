---
type: regex
target: { source: file, path: docs/conventions/developer-experience.md }
pattern: '^(?=[\s\S])(?![\s\S]*?(?:^|\n)## (?!Not yet[ \t]*(?:\n|(?![\s\S])))[^\n]*(?:\n(?!<!-- developer-experience: source=(?:chosen|default) -->)|(?![\s\S])))'
arm: with-only
---
