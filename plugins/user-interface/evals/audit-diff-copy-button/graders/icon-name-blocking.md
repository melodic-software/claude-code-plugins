---
type: llm
arm: both
---
PASS only if the review reports that the icon-only copy button (it renders only `CopyIcon` or
`CheckIcon`, no text) has no accessible name, grades that finding Blocking (or the review's most
severe level, however it is named), and gives as the fix a name that says the action, for example
`aria-label="Copy code"`, or visible text such as "Copy". FAIL if the review does not mention the
missing name, grades it below its most severe level (for example as a suggestion or nit), or fixes
it with a name that describes the icon instead of the action, such as `aria-label="Copy icon"` or
`aria-label="Clipboard"`.
