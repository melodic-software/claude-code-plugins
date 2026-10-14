---
type: regex
pattern: '(?:^|[\n.!?;,]|:(?=\s)|\b(?:and|but|then|so)\b)(?:(?!\b(?:don[''’]?t|do not|doesn[''’]?t|does not|no need|skip\w*|without|never|instead of|rather than|avoid\w*)\b)[^\n.!?;,])*?(?:/?session-flow:workflow\b|\bsession-flow workflow\b|\bworkflow (?:skill|navigat\w*|router)\b|\bnext (?:stage|step) (?:in|of) the workflow\b)'
flags: i
arm: both
---
