---
type: regex
target: { source: file, path: docs/conventions/developer-experience.md }
pattern: '^---\n(?:(?!---\n)[^\n]*\n)*?written_against: developer-experience@\d+\.\d+\.\d+[ \t]*\n(?:(?!---\n)[^\n]*\n)*?---(?:\n|(?![\s\S]))'
arm: with-only
---
