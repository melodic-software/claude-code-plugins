---
type: regex
pattern: '(?:^|[\n.!?;,]|:(?=\s)|\b(?:and|but|then|so)\b)(?:(?!\b(?:don[''’]?t|do not|doesn[''’]?t|does not|no need|skip\w*|without|never|instead of|rather than|avoid\w*)\b)[^\n.!?;,])*?(?:/?planning:(?:design|plan)\b|\bimplementation plan\b|\bplan (?:step|phase)\b|\b(?:write|create|draft|produce|run|make) (?:a|the) (?:implementation )?plan\b|\bplan the (?:implementation|change|work)\b)(?![^\n.!?;]{0,30}\b(?:isn[''’]?t|is not|not needed|unnecessary|adds nothing)\b)'
flags: i
arm: both
---
