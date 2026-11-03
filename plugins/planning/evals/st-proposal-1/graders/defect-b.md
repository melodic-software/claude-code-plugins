---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+(?:\w+\s+)?(?:issue|problem|concern|risk|finding|gap|defect)s?\b|\bnot\s+(?:a|an)\s+(?:\w+\s+)?(?:issue|problem|concern|risk|gap|defect)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good)\b|\bno\s+need\s+to\b|\bdon''t\s+see\s+(?:a|any)\b))(?!(?![^\n]*\b(?:but|however|contradict\w*|actually|yet|though|although)\b)[^\n]*(?:\bnot\b|n''t\b|\bnever\b|\bno\b|\bwithout\b)\s+(?:\w+\s+){0,2}(?:retr|re-?send|resend|loop|attempt|multiple|more\s+than))(?=[^\n]*(?:\bsend_sms\b|\bgateway\.py\b|\bgateway\s+client\b|\bgateway\s+(?:code|module)\b))[^\n]*(?:\bretries\b|\bretrying\b|\bretry\s+loop\b|\b(?:will|can|may|does|would)\s+retry\b|\bre-?sends?\b|\bloops?\b|\b(?:3|three)\s+(?:attempts|tries|times|requests|calls)\b|\bmultiple\s+(?:attempts|requests|calls|sends)\b|\bmore\s+than\s+one\s+(?:request|attempt|call)\b|\bseveral\s+(?:attempts|requests|calls)\b)'
flags: mi
target: last_message
---
