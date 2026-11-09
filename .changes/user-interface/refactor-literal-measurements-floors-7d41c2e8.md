---
bump: minor
---

### Changed

- Each measurement floor is stated once with its source: contrast in `color/contrast.md`, the 44 and 24 target floors (WCAG 2.5.5 AAA and 2.5.8 AA), the input floor (WebKit's standard font size) and reflow (WCAG 1.4.10) in `touch-web.md`, and the body-text floor (USWDS) in `typography.md`; other references point there and code examples keep their number.
- `/user-interface:audit` reports a project value below a measurement floor even when a project token sets it, naming the floor and its source, and never rewrites it: below a WCAG AA floor is Blocking, below an AAA or guidance floor is Should fix. Tags now follow that rule: large text, non-text and informative placeholder contrast and the focus ring color move from Important to Blocking; input text under the input floor moves from Blocking to Important (it still blocks a `launch`); a target under the 24 floor and content that fails reflow are new Blocking findings, and a two-color focus ring under 9:1 apart is a new Important one.
- The audit reports a press scale below `animation.scale.press_min` as a Suggestion.
