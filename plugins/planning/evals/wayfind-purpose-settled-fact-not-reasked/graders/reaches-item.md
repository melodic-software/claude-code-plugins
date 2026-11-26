---
type: regex
pattern: '^(?=[\s\S]*?(?:Choose the delivery channel|#?703\b))[\s\S]*?(?:^|\n)(?![^\n]*\b(?:claim\w*|(?:shall|should|can|may) (?:I|we) (?:start|run|invoke|open|claim|work on|pick up|take(?: up)?|begin)|(?:do you )?want (?:me )?to (?:start|run|work on|pick up|take up|begin)|ready (?:for me )?to (?:start|begin)|proceed|go ahead)\b)[^\n]*\b(?:deliver\w*|channels?|retention|retain\w*|kept|keep|delete\w*|deleting\w*|deletion\w*|purg\w*|SFTP|S3|recipients?|receive\w*|receiving\w*|send|sent)\b[^\n]*\?'
flags: i
---
