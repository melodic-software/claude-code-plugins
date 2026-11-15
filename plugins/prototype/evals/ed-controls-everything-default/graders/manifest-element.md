---
type: regex
target: trace
arm: with-only
pattern: '"name":"(?:Write|Edit)","input":\{[^\n]*?<script(?=[^>]*type=\\"application/json\\")[^>]*id=\\"prototype-controls\\"|"name":"Bash","input":\{(?=[^\n]*?(?:<<|\btee\b|\s>>?\s))[^\n]*?<script(?=[^>]*type=\\"application/json\\")[^>]*id=\\"prototype-controls\\"'
---
