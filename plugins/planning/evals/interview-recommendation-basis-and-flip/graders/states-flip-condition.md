---
type: regex
pattern: '(?:^|[.;!?\n])(?!(?:(?!\b(?:would|could|should) (?:flip|change|switch|reverse)\b|\bflips?\b)[^.;!?\n])*?(?:\b(?:nothing|never|not|no)\b|n[''’]t\b))(?:(?!\b(?:would|could|should) (?:flip|change|switch|reverse)\b|\bflips?\b)[^.;!?\n])*(?:\b(?:would|could|should) (?:flip|change|switch|reverse)\b|\bflips?\b)|\bchanges? (?:if|when)\b|\brecommend\w*\b[^\n]*\bunless\b|\bif instead\b|\bI(?:[''’]d| would) (?:switch|flip|change|pick|recommend|choose|go with)\b[^\n]{0,80}\binstead\b|\binstead\b[^.\n]{0,40}\bif\b|\bbreaks? (?:this|the|that|my) recommendation\b|\bswitch(?:es)? (?:to\b[^.\n]{0,60})?(?:if|when)\b|\brevisit (?:if|when)\b'
flags: i
arm: both
---
