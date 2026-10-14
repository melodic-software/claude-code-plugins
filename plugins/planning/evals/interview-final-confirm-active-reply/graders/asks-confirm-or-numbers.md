---
type: regex
pattern: '^(?![\s\S]*(?:\bno need|n[''’]t need|\bnot need|n[''’]t have|\bnot have) to (?:confirm|give|tell|list|name|send|reply)\b)(?![\s\S]*\bno (?:confirmation|reply|answer) (?:is )?needed\b)[\s\S]*?(?:\bconfirm\b[^\n]{0,200}\b(?:numbers?|Q\d*|ids?|which (?:items?|questions?|rows?))\b|\b(?:give|tell|list|name|send|share|reply with)\b[^\n]{0,60}\b(?:numbers?|Q\d*|ids?)\b[^\n]{0,80}\bchange\b)'
flags: i
arm: both
---
