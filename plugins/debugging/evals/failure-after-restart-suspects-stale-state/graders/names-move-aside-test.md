---
type: regex
pattern: '(?:\bmv\b|\bmov(?:e|ed|es|ing)\b|\brenam(?:e|ed|es|ing)\b|\baside\b)[^\n]{0,100}(?:profile\.lock|session\.json|index\.json|settings\.json|\bcache\b|\.lock\b)|(?:profile\.lock|session\.json|index\.json|settings\.json|\bcache\b)[^\n]{0,100}(?:\baside\b|\.bak\b|\.old\b|\brenam(?:e|ed|es|ing)\b|\bmov(?:e|ed|es|ing)\b)'
flags: i
---
