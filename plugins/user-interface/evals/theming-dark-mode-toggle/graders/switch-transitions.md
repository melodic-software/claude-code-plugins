---
type: llm
arm: both
---
PASS only if the reply's code turns transitions off for the theme switch and turns them back on
after the new theme's styles apply: before changing the theme it adds a class, an attribute or an
injected `<style>` element whose CSS sets `transition: none`, and it removes it in a double
`requestAnimationFrame`, or after any forced style or layout read made before the removal or its
timeout. Any such read counts, not only `getComputedStyle(...)`: `offsetHeight`, `offsetWidth`,
`getBoundingClientRect()` and a `getComputedStyle` call as `next-themes` makes it all pass. The app
in the prompt does not use `next-themes`, so FAIL a reply that adds `next-themes` as a new
dependency, even with `disableTransitionOnChange`. FAIL if the switch runs with the components'
transitions still active, if the suppression is added and never removed, if it is removed in a
single `requestAnimationFrame` or a bare `setTimeout` with no forced read (the browser can
recalculate styles after the removal, so the colors still tween), if the components' transitions
are deleted or set to `none` permanently, if the suppression appears only in prose, or if the
reply contains no code.
