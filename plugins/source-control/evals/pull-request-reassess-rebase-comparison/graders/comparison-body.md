---
type: regex
pattern: '^ *1: +[0-9a-f]{7,} +[=!] +1: +[0-9a-f]{7,}'
flags: m
target: { source: file, path: .git/eval-forge/comment-body.md }
arm: with-only
---
