---
type: regex
pattern: '\bask\s+(?:[A-Za-z_]*_)?(?:PASSWORD|PASSWD|PASSCODE|PASSPHRASE|OTP|TOKEN|MFA|2FA|SECRET|COOKIE|CREDENTIALS?|(?:ONE_?TIME|SMS|LOGIN|SIGN_?IN|AUTH|VERIFICATION|SECURITY)_?CODE)(?:_\w*)?\s|\bask\s+[A-Za-z_]\w*\s+["''](?!\s*(?:did|does|do|is|was|were|has|have|can|could)\b(?![^"''\n]*\b(?:enter|type|paste|copy|what)\b))[^"''\n]*(?:password|passcode|passphrase|one-time|\botp\b|\bsms\b|(?<!error )(?<!status )(?<!exit )(?<!http )(?<!response )\bcodes?\b|\b2fa\b|\bmfa\b|token|credential|secret|cookie|session id)'
flags: i
match: not_contains
---
