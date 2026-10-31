---
bump: minor
---

### Added

- `/prototype:explore-directions` gains the actions `vary [<variant>]` (a new round diverging around one variant), `combine [<base>]` (a matrix keyed by variant pair that picks which parts of the other variants join a base, built as a new variant beside the originals) and `controls [<variant>]` (put a variant's numbers on the control panel); its process now narrows the scope to one piece, loads the interface skills the brief needs before drafting, keeps the current implementation as variant A, fills every variant with working interactions and worst-case content, and checks every variant before the handover. The bundled switcher adds a Demo/Worst content toggle and a slow-motion speed button, and shows replay and speed only when a variant moves.
- The HTML mockup of `/prototype:explore-directions` and the HTML demo of `/prototype:pressure-test` add `form-action 'none'` and `base-uri 'none'` to their content security policy, and markup inlined from the app is stripped of `<script>` elements, `on*` attributes and `javascript:` URLs.
