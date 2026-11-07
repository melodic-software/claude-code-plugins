---
type: llm
arm: both
---
Expectations: "The answer prefers the component library already in the project, or explains
why it cannot cover a date picker" and "The answer does not propose replacing the installed
library".

The project's package.json lists Radix primitives (`@radix-ui/react-dialog`,
`@radix-ui/react-dropdown-menu`). PASS only if the answer prefers Radix (or a picker built on the
same primitives) or explains that Radix has no date picker and picks one that fits beside it, and
does not propose replacing Radix. FAIL if it proposes swapping the dialogs and menus to another
library, or recommends a full component library for the picker with no word on the installed one.
