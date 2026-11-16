---
type: regex
target: trace
arm: with-only
pattern: '"name":"(?:Write|Edit|Bash)","input":\{(?=[^\n]*?id=\\"prototype-controls\\")(?=[^\n]*?\\"group\\":(?: |\\[nt])*\\"layout\\")(?=[^\n]*?\\"group\\":(?: |\\[nt])*\\"typography\\")[^\n]*?\\"group\\":(?: |\\[nt])*\\"color\\"'
---
