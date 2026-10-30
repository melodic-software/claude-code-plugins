---
type: regex
pattern: '^\s*-{3}[^\n]*\n[\s\S]*?\bdialect:[ \t]*`?dbml`?[ \t]*\n(?:[\s\S]*?\n)?-{3}[\s\S]*?```dbml[ \t]*\n'
target: { source: file, path: .work/library-loans/design/entity-relationships.md }
---
