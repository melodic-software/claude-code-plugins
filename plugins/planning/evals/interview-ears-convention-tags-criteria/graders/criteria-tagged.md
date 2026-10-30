---
type: regex
pattern: '(?:^|\n)[-*]\s+`?AC\d+`?:\s+`?\[(?:ubiquitous|event-driven|state-driven|unwanted-behavior|optional-feature)\]'
target: { source: file, path: .work/export-retry/PLAN.md }
---
