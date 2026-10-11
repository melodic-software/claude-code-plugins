---
type: regex
target: { source: file, path: src/app.css }
arm: both
pattern: '^:root \{\n  --brand: #1f6feb;\n  --ink: #1b1f24;\n\}\n\n\.button \{\n  color: var\(--ink\);\n  background: var\(--brand\);\n  margin-left: 8px;\n  transition: all 400ms ease-in;\n\}\n\n\.button:hover \{\n  background: #174ea6;\n\}\n\n\.button:focus \{\n  outline: none;\n\}\n$'
---
