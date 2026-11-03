---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+(?:issue|problem|concern|risk|finding|gap|defect)s?\b|\bnot\s+(?:a|an)\s+(?:\w+\s+)?(?:issue|problem|concern|risk|gap|defect)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good)\b|\bno\s+need\s+to\b|\bdon''t\s+see\s+(?:a|any)\b))(?!(?![^\n]*\b(?:but|however|actually|yet|though|although)\b)[^\n]*(?:\bnot\b|n''t\b|\bnever\b)\s+(?:\w+\s+){0,2}(?:overlap|concurrent|race|collid|parallel))(?=[^\n]*(?:\bcompact\w*|\bmanifest(?:\.json)?\b|\bcron\w*|\*\/5\b))(?:[^\n]*(?:\btwo\s+(?:runs|instances|copies|compactions|processes|passes)\b|\bsecond\s+(?:run|instance|copy|compaction|pass)\b|\bno\s+(?:flock|lock\w*|mutual\s+exclusion)\b|\bwithout\s+(?:a\s+|any\s+)?(?:flock|lock\w*)\b|\blacks?\s+(?:a\s+)?(?:flock|lock\w*)\b|\blost\s+updates?\b)|(?=[^\n]*(?:\bruns?\b|\bpasses\b|\binstances?\b|\*\/5\b|\beight\b|\b8\b|\bfive\b|\bmanifest\b|\bflock\b|\bcron\b))[^\n]*(?:\boverlap\w*|\bconcurrent\w*|\bsimultaneous\w*|\bin\s+parallel\b|\brac(?:e|es|ing)\b))'
flags: mi
target: last_message
---
