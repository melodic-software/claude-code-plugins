---
type: regex
pattern: '\b(?:sounds?|looks?|seems?) (?:good|right|ok(?:ay)?|fine)\?|\b(?:does|do) (?:this|that|everything|it) (?:look|sound|seem) (?:good|right|ok(?:ay)?|fine)\?|\b(?:any|other) (?:thoughts|concerns|feedback)\?|\b(?:ok(?:ay)?|good to go|all good)\?|\bis (?:this|that|it|everything) (?:correct|right|accurate)\?|(?:^|[\s*])(?:agreed|makes? sense|correct|right)\?|\b(?:shall|should|can|may) I (?:proceed|go ahead|continue)\?|\bok(?:ay)? to (?:proceed|go ahead|lock|continue)\b[^?\n]{0,40}\?'
flags: i
match: not_contains
arm: both
---
