---
type: regex
flags: i
pattern: 'assistant\.js(?::L?|#L| line | lines )(?:1[19]|2[01])\b[\s\S]{0,800}?(?:prompt injection|inject|model(?:''s)? (?:output|reply|response|JSON)|LLM(?:''s)? (?:output|reply|response)|model-(?:chosen|controlled|supplied|generated)|LLM-(?:chosen|controlled|supplied|generated)|only (?:in|by) the (?:system )?prompt|system prompt)|(?:prompt injection|inject|model(?:''s)? (?:output|reply|response|JSON)|LLM(?:''s)? (?:output|reply|response)|model-(?:chosen|controlled|supplied|generated)|LLM-(?:chosen|controlled|supplied|generated)|only (?:in|by) the (?:system )?prompt|system prompt)[\s\S]{0,800}?assistant\.js(?::L?|#L| line | lines )(?:1[19]|2[01])\b'
---
