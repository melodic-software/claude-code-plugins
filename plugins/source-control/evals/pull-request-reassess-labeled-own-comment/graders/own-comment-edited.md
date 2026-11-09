---
type: regex
pattern: '"command":"comment edit","pr":512,"args":\["9001","<!-- source-control-reassess -->'
match: 'count:1'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
