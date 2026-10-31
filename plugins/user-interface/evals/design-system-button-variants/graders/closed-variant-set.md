---
type: llm
arm: both
---
PASS only if the docs in the reply list the Button variants as exactly the three the code's union
defines (`primary`, `secondary`, `danger`) and close the set in so many words: nothing else exists,
any other variant is a bug or an error, or the agent must not use a variant outside the list. A
name such as `ghost` or `destructive` is fine only when the docs show it as the thing not to use
(an incorrect example or a "never" line). FAIL if the docs present any variant the code does not
define (`ghost`, `outline`, `link`, `destructive`, `tertiary`) as available, if they list the three
variants without saying the set is closed, if the variants appear only in prose outside the docs
while the docs themselves leave them open, or if the reply contains no docs.
