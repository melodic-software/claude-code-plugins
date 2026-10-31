---
type: llm
arm: both
---
PASS only if the reply's code keeps the Save button the same width when its label changes to
"Saving…": a nonzero length or percentage on the button's `min-width`, `width`, `min-inline-size`
or `inline-size`, a Tailwind `min-w-*` or `w-*` class on it that sets a length (`min-w-28`, `w-32`,
`min-w-[7rem]`), or both labels stacked in one grid cell with the inactive one hidden by
`visibility: hidden` or `opacity: 0` so the box takes the wider one. FAIL if the button has no
fixed, minimum or reserved width in the code; if its only width is a content keyword
(`fit-content`, `max-content`, `min-content`, `auto`, or the Tailwind `w-fit`, `w-max`, `w-min`,
`w-auto`, `min-w-fit`, `min-w-max`, `min-w-min`, `min-w-0`), which sizes the button to whichever
label it shows and so still changes its width; if the width appears only in prose; if the only
change to the button is `tabular-nums` or a font change; if the fix removes the "Saving…" label
instead of holding the width; or if the reply contains no code.
