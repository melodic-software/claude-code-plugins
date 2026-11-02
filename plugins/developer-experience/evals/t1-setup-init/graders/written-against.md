---
type: regex
target: { source: file, path: docs/conventions/developer-experience.md }
pattern: '^-{3}\n(?:(?!-{3}\n)[^\n]*\n)*?written_against: developer-experience@\d+\.\d+\.\d+[ \t]*\n(?:(?!-{3}\n)[^\n]*\n)*?-{3}(?:\n|(?![\s\S]))'
arm: with-only
---
