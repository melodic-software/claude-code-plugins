---
type: regex
pattern: '(?:^|\n)[-*]?\s*`?Overrides bundled default\W{0,4}[A-Za-z][^\n]{0,160}?\W{0,4}per\W{0,4}(?:\./)?docs/standards/integrations\.md'
target: { source: file, path: .work/address-validation/PLAN.md }
---
