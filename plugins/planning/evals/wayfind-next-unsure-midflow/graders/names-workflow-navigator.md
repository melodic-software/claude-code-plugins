---
type: regex
pattern: '(?:^|[.!?;,\n\u2014\u2013]\s*)(?:(?!\b(?:not|never|skip|instead of|rather than|unless)\b|n''t\b|\bno need\b)[^.!?;,\n\u2014\u2013])*?(?:/?session-flow:workflow\b|\bworkflow (?:skill|navigat\w*|router)\b|\bnext (?:stage|step) (?:in|of) the workflow\b)'
flags: i
arm: both
---
