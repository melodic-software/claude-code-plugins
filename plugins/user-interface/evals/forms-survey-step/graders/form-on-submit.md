---
type: llm
arm: both
---
PASS only if the reply's code renders the step inside a form that does the step's work on submit: a
`<form>` (or the project's capitalized `Form` component) whose `onSubmit` handler or `action` saves
the answer, so Enter or a submit-type Continue submits it. Any formatting
counts, including a multi-line tag or a code block with template literals before the form. FAIL if
there is no form, if the form's `onSubmit` only prevents the default while Continue's `onClick` does
the saving (so submitting the form saves nothing), if the form has neither `onSubmit` nor `action`,
if the form appears only in prose, or if the reply contains no code.
