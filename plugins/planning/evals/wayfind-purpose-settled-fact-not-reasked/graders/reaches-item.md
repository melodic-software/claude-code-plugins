---
type: regex
pattern: '^(?=[\s\S]*?(?:Choose the delivery channel|#?703\b))[\s\S]*?(?:^|\n)(?![^\n]*\b(?:claim\w*|(?:shall|should) (?:I|we) (?:start|work on|pick up|take up|begin)|want me to|proceed|go ahead)\b)[^\n]*\b(?:deliver\w*|channels?|retention|retain\w*|kept|keep|delete\w*|deleting\w*|deletion\w*|purg\w*|SFTP|S3|recipients?|receive\w*|receiving\w*|send|sent)\b[^\n]*\?'
flags: i
---
