---
type: llm
arm: both
---
PASS only if the review reports that the copied confirmation (the swap from `CopyIcon` to
`CheckIcon` for two seconds) is visual only, so a screen reader user hears nothing when the copy
succeeds, and gives as the fix a live region that announces it: an element with `role="status"` or
`aria-live="polite"`, present in the DOM before the message is put into it, whose text becomes
something like "Copied". FAIL if the review does not mention the silent confirmation, if its fix
only changes the button's `aria-label` to "Copied" with no live region, or if the fix mounts the
live region together with its first message (for example rendering
`{copied && <span role="status">Copied</span>}`).
