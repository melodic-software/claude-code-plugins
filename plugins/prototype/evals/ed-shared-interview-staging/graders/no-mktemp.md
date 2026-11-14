---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"Bash","input":\{[^\n]*?\bmktemp\b(?:(?!\\n)[^;&|)\n])*?(?:staging|manifest|interview-data)|"name":"(?:Write|Edit)","input":\{"file_path":"(?![^"]*interview-data/staging/)[^"]*manifest\.json"|"name":"Bash","input":\{[^\n]*?(?:(?<=[\s}])>>?|\btee\b)\s*(?:\\")?(?![^\s"\\]*staging/)[^\s"\\]*manifest\.json'
---
