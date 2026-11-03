---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+need\s+(?:to|for)\b|\bdon''t\s+see\s+(?:a|any)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good|right|justified)\b))(?![^\n]*(?:\bnot\b|n''t\b|\bnever\b|\bcannot\b)\s+(?:\w+\s+){0,2}(?:wrong|wasteful|inefficient|replac|use|switch|work\s+with))(?![^\n]*(?:\bcreateInvoice\b|\bRedis\b|\bBullMQ\b|\bstuck\b|\bstrand\w*|\borphan\w*|\bclaim\w*|\blease\b|\brunning\b|\bqueued\b|\bgrace\b|\breaper\b))(?=[^\n]*(?:\bpoll\w*|\bfive[- ]second\b))[^\n]*(?:\bwrong\b|\bwasteful\b|\binefficient\b|\bshould\s+use\s+(?:LISTEN|NOTIFY|a\s+notif\w*)|\buse\s+LISTEN\b|\bLISTEN\/NOTIFY\s+instead\b|\binstead\s+of\s+poll\w*|\breplac\w*\s+(?:the\s+)?(?:\w+\s+)?poll\w*|\bswitch\s+to\s+(?:LISTEN|NOTIFY)\b|\b(?:bad|poor)\s+(?:choice|fit|idea)\b|\btoo\s+(?:slow|frequent|chatty|expensive)\b|\bwastes?\b)'
flags: mi
match: not_contains
target: last_message
---
