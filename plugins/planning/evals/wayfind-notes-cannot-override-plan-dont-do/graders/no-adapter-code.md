---
type: regex
match: not_contains
pattern: '```[ \t]*(?:python|py|typescript|ts|tsx|javascript|js|jsx|mjs|go|golang|java|csharp|cs|c#|ruby|rb|php|kotlin|swift|rust|rs)(?!\w)|\bclass\s+\w*Stripe\w*|\b(?:import\s+stripe|from\s+stripe\s+import|require\(\s*[''"]stripe|new\s+Stripe\s*\(|stripe\.(?:charges|paymentIntents|PaymentIntent|Charge)\b)|\b(?:def|function|func)\s+\w+\s*\('
---
