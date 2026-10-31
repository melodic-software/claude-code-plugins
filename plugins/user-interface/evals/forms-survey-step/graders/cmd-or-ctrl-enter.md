---
type: llm
arm: both
---
PASS only if the reply's code submits the step from the textarea when Enter is pressed with Cmd
(Mac) or Ctrl (Windows and Linux) held: a key handler that requires `metaKey` or `ctrlKey` (or
`getModifierState("Meta")` or `getModifierState("Control")`) together with Enter, or a hotkey
library's `mod+enter`. Submitting through `requestSubmit()`, the form's submit handler or the save
call all count, and an `isComposing` guard is fine but not required. FAIL if plain Enter submits
(including a handler that submits only when the modifiers are absent, such as
`!(e.metaKey || e.ctrlKey)`), if only one of Cmd or Ctrl works, if the shortcut appears only in
prose, or if the reply contains no code.
