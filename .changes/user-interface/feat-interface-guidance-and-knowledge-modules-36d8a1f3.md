---
bump: minor
---

### Changed

- Motion guidance for `/user-interface:write-animation`, `/user-interface:audit` and `/user-interface:write-css` grows: graded findings for frequency, purpose, easing, duration, origin, paired timing, interruption, missing exits, page-load entrances, stagger, reduced motion, hover motion and frame cost; permanent exits accelerate away on their own curve and run shorter than their entrance; element-scale motion stays under 300ms with a separate page duration; a named easing library; component recipes for section entrances, exits, icon swaps and tooltip groups; and write-css recipes for a popover that scales from its trigger, a popover inside a modal, a reduced-motion swap and a hover that keeps its hit area.
