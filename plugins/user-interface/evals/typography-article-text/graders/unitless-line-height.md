---
type: llm
arm: both
---
PASS only if every line height the reply's CSS sets on the article body text is unitless: a bare
number (`line-height: 1.6`, `line-height: 1.6 !important`, or the line-height part of the `font`
shorthand such as `font: 1rem/1.6 serif`), or a custom property or token that the reply defines or
describes as a unitless number (`line-height: var(--leading-body)` with `--leading-body: 1.6`, or
the project's leading token when the reply says it is unitless).
FAIL if the reply sets the body line height in `px`, `rem`, `em` or `%` anywhere in its CSS, keeps
the proposed `line-height: 24px` as the value to use, gives no body line height at all, or sets a
unitless value only on headings while the body keeps a value with a unit. Mentioning `24px` in prose
as the value to avoid is not a failure.
