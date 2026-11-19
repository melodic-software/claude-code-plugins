---
type: regex
target: trace
arm: with-only
pattern: '"name":"(?:Write|Edit|Bash)","input":\{(?=[^\n]*?id=\\"prototype-controls\\")(?=[^\n]*?\\"group\\":(?: |\\[nt])*\\"layout\\")(?=[^\n]*?\\"group\\":(?: |\\[nt])*\\"typography\\")[^\n]*?\\"group\\":(?: |\\[nt])*\\"color\\"|"name":"Write","input":\{(?=[^\n]*?"file_path":"(?:[^"]*/)?([^"/]+\.(?:mjs|cjs|js|py))")(?=[^\n]*?(?:(?<![A-Za-z0-9_])(?:write|append)File(?:Sync)?\(|(?<!stdout)\.write(?:_text)?\())(?=[^\n]*?\.html)(?=[\s\S]*?"name":"Bash","input":\{"command":"(?:[^"\\]|\\.)*?(?:(?<=\\[nt])|(?<![A-Za-z0-9_.-]))(?:node|bun(?: run)?|python3?)\s+(?:\\"|\x27)?(?:[^\s"\\\x27]*/)?\1(?![A-Za-z0-9_.-]))(?=[^\n]*?(?:(?<=\\[nt])|(?<![A-Za-z0-9_$]))(?:\\"|\x27)?group(?:\\"|\x27)?(?: |\\[nt])*:(?: |\\[nt])*(?:\\"|\x27)layout(?:\\"|\x27))(?=[^\n]*?(?:(?<=\\[nt])|(?<![A-Za-z0-9_$]))(?:\\"|\x27)?group(?:\\"|\x27)?(?: |\\[nt])*:(?: |\\[nt])*(?:\\"|\x27)typography(?:\\"|\x27))[^\n]*?(?:(?<=\\[nt])|(?<![A-Za-z0-9_$]))(?:\\"|\x27)?group(?:\\"|\x27)?(?: |\\[nt])*:(?: |\\[nt])*(?:\\"|\x27)color(?:\\"|\x27)'
---
