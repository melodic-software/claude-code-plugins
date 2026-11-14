---
type: regex
target: trace
pattern: '"name":"Write","input":\{[^\n]*?staging/[^\"\\]+\.html[^\n]*?<![Dd][Oo][Cc][Tt][Yy][Pp][Ee] [Hh][Tt][Mm][Ll]>|"name":"Bash","input":\{[^\n]*?(?:>|\btee\b)\s*(?:\\")?[^\s"\\]*staging/[^\s"\\]+\.html[^\n]*?<![Dd][Oo][Cc][Tt][Yy][Pp][Ee] [Hh][Tt][Mm][Ll]>|"name":"(?:Write|Bash)","input":\{[^\n]*?<![Dd][Oo][Cc][Tt][Yy][Pp][Ee] [Hh][Tt][Mm][Ll]>(?:\\\\?n|\s)*<[Hh][Tt][Mm][Ll][\s\S]*?"name":"Bash","input":\{"command":"[^\n]*?\b(?:node|python3?|cp|cat|install)\b[^\n]*?staging/'
---
