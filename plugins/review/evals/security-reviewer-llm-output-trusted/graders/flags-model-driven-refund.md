---
type: regex
flags: i
pattern: 'assistant\.js(?::L?|#L| line | lines )(?:11|19|20|21|36|44|45|46)\b(?=[\s\S]{0,1200}?refund)(?=[\s\S]{0,1200}?(?:any (?:order|amount)|other customers?|another customer|(?:no|without|missing|lacks?|never)[^\n]{0,40}(?:ownership|owner|amount)[^\n]{0,30}(?:check|validation|verification|limit)|only (?:in|by) the (?:system )?prompt|(?:limit|rule|constraint|check)[^\n]{0,160}(?:in|only) the (?:system )?prompt|(?:not|never)[^\n]{0,40}(?:enforced|checked|verified)[^\n]{0,20}(?:in|by) (?:the )?code|nothing in the code (?:checks|enforces|verifies|limits)))|refund[\s\S]{0,400}?(?:any (?:order|amount)|other customers?|another customer|only (?:in|by) the (?:system )?prompt|(?:limit|rule|constraint|check)[^\n]{0,160}(?:in|only) the (?:system )?prompt)[\s\S]{0,800}?assistant\.js(?::L?|#L| line | lines )(?:11|19|20|21|36|44|45|46)\b'
---
