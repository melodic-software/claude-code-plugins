---
type: regex
pattern: '(?:^|\n)#{1,6}[ \t]*[Aa]cceptance [Cc]riteria[^\n]*(?!(?:\n(?!#)[^\n]*)*?\n[ \t]*[-*][ \t]+`?AC\d+`?:[ \t]*(?![ \t]|`?\[(?:ubiquitous|event-driven|state-driven|unwanted-behavior|optional-feature)\]))(?:\n(?!#)[^\n]*)*?\n[ \t]*[-*][ \t]+`?AC\d+`?:[ \t]*`?\[(?:ubiquitous|event-driven|state-driven|unwanted-behavior|optional-feature)\]'
target: { source: file, path: .work/export-retry/PLAN.md }
---
