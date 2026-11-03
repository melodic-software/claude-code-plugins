---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+(?:\w+\s+)?(?:issue|problem|concern|risk|finding|gap|defect)s?\b|\bnot\s+(?:a|an)\s+(?:\w+\s+)?(?:issue|problem|concern|risk|gap|defect)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good)\b|\bno\s+need\s+to\b|\bdon''t\s+see\s+(?:a|any)\b))(?!(?![^\n]*\b(?:but|however|contradict\w*|actually|yet|though|although)\b)[^\n]*(?:\bnot\b|n''t\b|\bnever\b|\bno\b|\bwithout\b)\s+(?:\w+\s+){0,2}(?:duplicat|double|second\s+invoice))(?=[^\n]*(?:\bcreateInvoice\b|\binvoice\.ts\b|\b001_init\b|\binvoices\s+table\b|\binvoices_tenant_period\b))[^\n]*(?:\bnot\s+idempotent\b|\bnon-?idempotent\b|\bisn''t\s+idempotent\b|\bno\s+(?:unique|upsert|ON\s+CONFLICT|dedup\w*)\b|\bwithout\s+(?:a\s+|any\s+)?(?:unique|upsert|ON\s+CONFLICT)\b|\b(?:not|non-?)\s*unique\b|\bplain\s+insert\b|\bbare\s+insert\b|\bunconditional\w*\s+insert\w*|\bdoes(?:\s+not|n''t)\s+upsert\b|\bduplicate\s+(?:invoice|row|email|charge|PDF)s?\b|\bdouble[- ](?:invoice|bill|email|send)\w*|\bsecond\s+invoice\b|\binvoices?\s+twice\b|\bemails?\s+(?:the\s+\w+\s+)?(?:again|twice)\b)'
flags: mi
target: last_message
---
