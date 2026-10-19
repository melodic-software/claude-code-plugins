---
type: regex
pattern: '### Constraints(?:[^#]|#(?!#))*?\n- Quality requirement:(?=[^\n]*(?:\b2\s?(?:s|seconds?)\b|\bdown\b|unavailable|\bfails?\b|time\s?out|timeout|slower))(?=[^\n]*(?:proceed|continue[sd]?|continuing|continuation|fall\s?back|falls back|bypass|\bskip|\bwarn))'
flags: i
target: { source: file, path: .work/address-validation/PLAN.md }
---
