---
type: llm
arm: both
---
PASS only if the reply's code disables the signup form's submit button while the request is in
flight, so a second click cannot fire it: `disabled` bound to a submitting, pending, loading or busy
state that is true during the request (any variable name, react-hook-form's `isSubmitting`, or
`useFormStatus().pending` read in a component rendered inside the form). A label that says what is
happening ("Creating account…") is expected but not required. FAIL if the button stays enabled
during the request, if `disabled` is bound only to validity or to the negation of the pending
state, if `aria-disabled` is the only guard, if `useFormStatus` is called in the same component
that renders the `<form>` (its `pending` never turns true there), if the disabling appears only in
prose, or if the reply contains no code.
