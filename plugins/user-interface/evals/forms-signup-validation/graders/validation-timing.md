---
type: llm
arm: both
---
PASS only if the reply's code validates each signup field on blur or on submit rather than on every
keystroke: a react-hook-form `mode` of `"onBlur"`, `"onTouched"` or `"onSubmit"`, a validate call
inside an `onBlur` or submit handler, an error shown only once a touched or submitted flag is set,
or CSS `:user-invalid`. Re-validating on change after a field has shown an error is fine. FAIL if
the code runs validation inside `onChange` with no blur, touched or submitted gate (an unrelated
`onBlur` elsewhere does not count), if it sets `mode: "onChange"` or `mode: "all"`, if the timing
appears only in prose while the code validates on every keystroke, or if the reply contains no
code. Prose that names `mode: "onChange"` as the thing to avoid does not fail a correct answer.
