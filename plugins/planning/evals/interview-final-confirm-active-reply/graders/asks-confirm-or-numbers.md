---
type: regex
pattern: '\bconfirm\b[^\n]{0,200}\b(?:numbers?|Q\d+|which (?:items?|questions?|rows?))\b|\b(?:give|tell|list|name|send)\b[^\n]{0,60}\b(?:numbers?|Q\d+)\b[^\n]{0,80}\bchange\b'
flags: i
arm: both
---
