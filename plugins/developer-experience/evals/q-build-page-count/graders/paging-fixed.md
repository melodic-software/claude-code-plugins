---
type: regex
target: {source: file, path: src/Tarnquill.Core/Paging.cs}
pattern: 'return\s+(?:\(\s*total\s*\+\s*pageSize\s*-\s*1\s*\)\s*/\s*pageSize|\(?\s*total\s*/\s*pageSize\s*\)?\s*\+\s*\(\s*total\s*%\s*pageSize\s*(?:==\s*0\s*\?\s*0\s*:\s*1|(?:!=|>)\s*0\s*\?\s*1\s*:\s*0)\s*\)|total\s*%\s*pageSize\s*==\s*0\s*\?\s*total\s*/\s*pageSize\s*:\s*total\s*/\s*pageSize\s*\+\s*1|total\s*(?:==|<=)\s*0\s*\?\s*0\s*:\s*\(\s*total\s*-\s*1\s*\)\s*/\s*pageSize\s*\+\s*1)\s*;|Math\.Ceiling\((?=[^;\n]*\btotal\b)(?=[^;\n]*\bpageSize\b)(?=[^;\n]*(?:\((?:double|decimal|float)\)|\b1\.0))|if\s*\(\s*total\s*%\s*pageSize\s*==\s*0\s*\)\s*\{?\s*return\s+total\s*/\s*pageSize\s*;|if\s*\(\s*total\s*%\s*pageSize\s*(?:!=|>)\s*0\s*\)\s*\{?\s*return\s+total\s*/\s*pageSize\s*\+\s*1\s*;\s*\}?\s*return\s+total\s*/\s*pageSize\s*;'
---
