---
type: regex
pattern: '(?<!than )(?<!not )(?<!instead of )(?:\ban?|\bas|\bin) integer (?:count of |number of )?minor[ _-]?units?\b|\w*minor\w*\s*:\s*int\b|\w*cents\w*\s*:\s*int\b|\bamount\b\s*:\s*int\b|smallest (?:currency )?unit[^\n]*\bint(?:egers?)?\b'
flags: i
target: { source: file, path: .work/invoice-totals/design/type-inventory.md }
---
