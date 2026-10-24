---
type: regex
pattern: '(?<![\s\S])(?![\s\S]*^Refactor checkpoint:)[\s\S]*?tdd_refactor_step`?\s*[=:]\s*`?off`?\s*\(`?[^)\n]*docs/conventions/testing\.yaml`?\)'
flags: m
---

Passes when the final reply carries the Settings line naming `tdd_refactor_step` as `off` from
`docs/conventions/testing.yaml`, and no line anywhere in it begins `Refactor checkpoint:`: with the
step off the skill writes no checkpoint. The lookbehind anchors the match at the start of the
reply, so the lookahead scans the whole reply, a checkpoint line before the Settings line
included. An empty or off-task reply fails, since the Settings line is required.
