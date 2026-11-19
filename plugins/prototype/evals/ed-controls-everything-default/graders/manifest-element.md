---
type: regex
target: trace
arm: with-only
pattern: '"name":"(?:Write|Edit)","input":\{(?=[^\n]*?"file_path":"[^"]*\.html")[^\n]*?<script(?=[^>]*type=[\\"\x27]+application/json)[^>]*id=[\\"\x27]+prototype-controls|"name":"Bash","input":\{"command":"(?=(?:[^"\\]|\\.)*?(?:>>?\s*(?:\\"|\x27)?[^\s"\\\x27]*\.html|\btee\b(?:\s+-a)?\s+(?:\\"|\x27)?[^\s"\\\x27]*\.html|\bsed\s+-i|\.write(?:_text)?\(|\b(?:write|append)File(?:Sync)?\())(?:[^"\\]|\\.)*?<script(?=[^>]*type=[\\"\x27]+application/json)[^>]*id=[\\"\x27]+prototype-controls|"name":"Write","input":\{(?=[^\n]*?"file_path":"(?:[^"]*/)?([^"/]+\.(?:mjs|cjs|js|py))")(?=[^\n]*?(?:(?<![A-Za-z0-9_])(?:write|append)File(?:Sync)?\(|(?<!stdout)\.write(?:_text)?\())(?=[^\n]*?\.html)(?=[\s\S]*?"name":"Bash","input":\{"command":"(?:[^"\\]|\\.)*?(?:(?<=\\[nt])|(?<![A-Za-z0-9_.-]))(?:node|bun(?: run)?|python3?)\s+(?:\\"|\x27)?(?:[^\s"\\\x27]*/)?\1(?![A-Za-z0-9_.-]))[^\n]*?<script(?=[^>]*type=[\\"\x27]+application/json)[^>]*id=[\\"\x27]+prototype-controls'
---
