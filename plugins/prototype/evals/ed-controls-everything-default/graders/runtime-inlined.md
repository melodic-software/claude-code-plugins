---
type: regex
target: trace
arm: with-only
pattern: '"name":"(?:Write|Edit)","input":\{(?=[^\n]*?"file_path":"[^"]*\.html")[^\n]*?Object\.defineProperty\(window, \\"uiFeedbackControls\\"|"name":"Bash","input":\{"command":"(?=(?:[^"\\]|\\.)*?(?:notes-bridge/controls\.js|Object\.defineProperty\(window, \\"uiFeedbackControls))(?=(?:[^"\\]|\\.)*?\.html)(?:[^"\\]|\\.)*?(?:>>?\s*(?:\\"|\x27)?[^\s"\\\x27]*\.html|(?:(?<=\\[nt])|(?<![A-Za-z0-9_]))tee\b(?:\s+-a)?\s+(?:\\"|\x27)?[^\s"\\\x27]*\.html|(?:(?<=\\[nt])|(?<![A-Za-z0-9_]))sed\s+-i|\.write(?:_text)?\(|(?:(?<=\\[nt])|(?<![A-Za-z0-9_]))(?:write|append)File(?:Sync)?\()|"name":"Bash","input":\{"command":"(?=(?:[^"\\]|\\.)*?(?:notes-bridge/controls\.js|Object\.defineProperty\(window, \\"uiFeedbackControls))(?=(?:[^"\\]|\\.)*?(?:(?<=\\[nt])|(?<![A-Za-z0-9_]))([A-Za-z_][A-Za-z0-9_]*)=(?:\\"|\x27)?[^\s"\\\x27;]*\.html)(?:[^"\\]|\\.)*?>>?\s*(?:\\"|\x27)?\$\{?\1\b'
---
