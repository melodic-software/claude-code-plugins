---
type: regex
match: not_contains
flags: i
arm: both
pattern: '(?:transition|animation)(?:-duration)?\s*:[^;{}\n]*?(?<![\w.])0*[1-9]\d*(?:\.\d+)?m?s\b|(?:transition|animation)(?:-duration)?\s*:[^;{}\n]*?(?<![\w])0?\.\d*[1-9]\d*m?s\b|@keyframes|\banimate\(|<motion\.|\bmotion\.\w+\('
---
