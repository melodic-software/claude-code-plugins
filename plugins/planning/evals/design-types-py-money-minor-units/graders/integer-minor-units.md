---
type: regex
pattern: 'minor[ _-]?units?|\w*_minor\b\s*:\s*int\b|\b\w*cents\b\s*:\s*int\b|\bamount\b\s*:\s*int\b|smallest (?:currency )?unit[^\n]*\bint'
flags: i
target: { source: file, path: .work/invoice-totals/design/type-inventory.md }
---
