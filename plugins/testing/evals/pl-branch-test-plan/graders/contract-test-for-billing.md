---
type: regex
pattern: '\b(?:contract[- ]tests?|consumer[- ]driven|pacts?)\b[^\n]{0,160}\b(?:BillingClient|billing[-_ ](?:service|client)|billing_client(?:\.py)?|create_invoice)\b|\b(?:BillingClient|billing[-_ ](?:service|client)|billing_client(?:\.py)?|create_invoice)\b[^\n]{0,200}\b(?:contract[- ]tests?|consumer[- ]driven|pacts?)\b|^[ \t]*(?:#{1,6}|\*\*)[^\n]*\b(?:contract[- ]tests?|consumer[- ]driven)\b[^\n]*\n(?:[ \t]*[-*\d|][^\n]*\n|[ \t]*\n){0,6}?[ \t]*[-*\d|][^\n]*\b(?:BillingClient|billing[-_ ](?:service|client)|billing_client|create_invoice)\b'
flags: 'mi'
target: 'last_message'
---
