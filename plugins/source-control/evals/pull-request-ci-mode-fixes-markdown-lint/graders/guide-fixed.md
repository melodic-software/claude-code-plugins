---
type: regex
pattern: '^(?![\s\S]*markdownlint-(?:disable|configure))(?![\s\S]*` npm test `)(?=[\s\S]*`npm test`)'
target: { source: file, path: docs/guide.md }
---
