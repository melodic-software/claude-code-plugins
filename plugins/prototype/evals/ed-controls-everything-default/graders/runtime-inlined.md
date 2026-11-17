---
type: regex
target: trace
arm: with-only
pattern: '"name":"(?:Write|Edit)","input":\{(?=[^\n]*?"file_path":"[^"]*\.html")[^\n]*?Object\.defineProperty\(window, \\"uiFeedbackControls\\"|"name":"Bash","input":\{"command":"(?=(?:[^"\\]|\\.)*?(?:notes-bridge/controls\.js|Object\.defineProperty\(window, \\"uiFeedbackControls))(?=(?:[^"\\]|\\.)*?\.html)(?:[^"\\]|\\.)*?(?:>>?\s*(?:\\"|\x27)?(?:[^\s"\\\x27]*\.html|\$\{?[A-Za-z_][A-Za-z0-9_]*)|\btee\b(?:\s+-a)?\s+(?:\\"|\x27)?[^\s"\\\x27]*\.html|\bsed\s+-i|\.write(?:_text)?\(|\b(?:write|append)File(?:Sync)?\()'
---
