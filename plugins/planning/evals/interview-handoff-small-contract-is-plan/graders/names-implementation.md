---
type: regex
pattern: '^(?![\s\S]*?(?:^|[\n.!?;,]|:(?=\s)|\b(?:and|but|then|so)\b)(?:(?!\b(?:don[''’]?t|do not|doesn[''’]?t|does not|no need|skip\w*|without|never|instead of|rather than|avoid\w*)\b)[^\n.!?;,])*?\b(?:run|use|invoke|start with|go to|next(?: step)?(?: is)?:?)\s*[`*]*/?planning:(?:plan|design)\b)[\s\S]*?(?:^|[\n.!?;,]|:(?=\s)|\b(?:and|but|then|so)\b)(?:(?!\b(?:don[''’]?t|do not|doesn[''’]?t|does not|no need|skip\w*|without|never|instead of|rather than|avoid\w*)\b)[^\n.!?;,])*?(?:/?implementation:implement\b|\b(?:straight|directly|right) (?:to|into) (?:implementation|implementing|coding|code|building)\b|\bproceed (?:directly |straight )?(?:to|with) (?:implementation|implementing|coding|the change)\b|\b(?:start|begin) (?:coding|building|implementing|the implementation|implementation)\b|\bimplement (?:it|the (?:change|rename))\b|\bimplement(?:ing)? (?:it |this |the change )?(?:now|directly|right away)\b)'
flags: i
arm: both
---
