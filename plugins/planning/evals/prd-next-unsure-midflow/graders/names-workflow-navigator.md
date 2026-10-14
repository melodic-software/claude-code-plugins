---
type: regex
pattern: '(?:^|[.;,!?\n\u2014\u2013])(?:(?!(?:\b(?:never|not|avoid|no need for)\b|n[''’]t\b)[^.;,!?\n\u2014\u2013]{0,15}(?:/?session-flow:workflow\b|\bsession[- ]flow workflow\b|\bworkflow (?:skill|navigat\w*|router)\b))[^.;,!?\n\u2014\u2013])*?(?:/?session-flow:workflow\b|\bsession[- ]flow workflow\b|\bworkflow (?:skill|navigat\w*|router)\b)'
flags: i
arm: both
---
