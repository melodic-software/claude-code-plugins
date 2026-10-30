---
type: regex
pattern: '^\s*-{3}[^\n]*\n(?=(?:(?!-{3})[^\n]*\n)*?[ \t]*scope:[ \t]*`?data`?[ \t]*\n)(?=(?:(?!-{3})[^\n]*\n)*?[ \t]*dialect:[ \t]*`?dbml`?[ \t]*\n)(?:(?!-{3})[^\n]*\n)*-{3}[\s\S]*?```dbml[ \t]*\n'
target: { source: file, path: .work/library-loans/design/entity-relationships.md }
---
