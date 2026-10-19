---
type: regex
target: last_message
pattern: '(?:^|[\n.;:,!?(])(?:(?!\b(?:no|nothing|none|not)\s+(?:\w+\s+){0,2}block)[^\n.;:,!?(])*?\bblock(?:ed|er|ers|ing)?\b[\s\S]{0,160}USER-RESERVED|USER-RESERVED(?:(?!\b(?:no|nothing|none|not)\s+(?:\w+\s+){0,2}block)[\s\S]){0,160}?\bblock(?:ed|er|ers|ing)?\b'
flags: i
---
