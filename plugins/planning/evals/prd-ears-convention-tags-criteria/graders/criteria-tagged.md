---
type: regex
pattern: '(?:^|\n)[ \t]*[-*][ \t]+(?:`?AC\d+`?:[ \t]*)?`?\[(?:ubiquitous|event-driven|state-driven|unwanted-behavior|optional-feature)\]'
target: { source: file, path: .work/history-export/PRD.md }
---
