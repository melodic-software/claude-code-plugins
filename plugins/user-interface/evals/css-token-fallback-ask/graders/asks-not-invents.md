---
type: llm
arm: both
---
PASS only if the answer says tokens.css has no warning or amber color, and asks the user how to
proceed (add a new token, with a proposed value clearly marked as a proposal, or reuse an existing
token) before delivering final CSS that depends on it. FAIL if it delivers `.alert--warning` with an
invented token or a literal amber color as the finished answer without asking, or never notices
the missing token.
