---
type: llm
arm: both
---
PASS only if the reply's code gives the textarea an accessible name other than its placeholder: a
`<label>` whose `htmlFor` matches the textarea's `id` (literal strings, a shared variable, `useId`
or matching template literals), a `<label>` that wraps the textarea or the project's `Textarea`
component, `aria-labelledby` naming an id that an element in the code has, or a non-empty
`aria-label`. FAIL if the placeholder is the only name, if the label sits beside the textarea
without `htmlFor` or wrapping, if `htmlFor` or `aria-labelledby` names an id nothing has, if the
label appears only in prose (including prose that quotes a label and then keeps the placeholder),
or if the reply contains no code.
