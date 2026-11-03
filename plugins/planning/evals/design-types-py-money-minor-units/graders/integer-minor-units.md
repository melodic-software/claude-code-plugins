---
type: regex
pattern: '\w*minor\w*\s*:\s*int\b|\w*cents\w*\s*:\s*int\b|\bamount\w*\s*:\s*int\b'
flags: i
target: { source: file, path: .work/invoice-totals/design/type-inventory.md }
---

Passes only on a typed integer field for the amount. Prose never passes, so a negated mention of
integer minor units cannot pass either.
