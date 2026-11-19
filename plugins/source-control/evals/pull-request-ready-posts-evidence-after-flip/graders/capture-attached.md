---
type: regex
pattern: '"command":"pr comment","pr":655,"args":\[[^\n]*"--attach","[^"\n]*cart\.png"'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
