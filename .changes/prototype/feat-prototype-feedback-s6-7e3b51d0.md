---
bump: minor
---

### Added

- The notes host page's dock has two tabs, Notes and Controls, in the WAI-ARIA tabs pattern: the
  arrow keys, Home and End move between them, and the dock button and N still hide and show it.
- A mockup's controls come from one `prototype-controls` manifest, checked against the new
  `notes-bridge/controls.schema.json`, and are drawn by the controls runtime
  `notes-bridge/controls.js` with one registry of control types (range, color, select, toggle,
  radio). Each control writes a CSS variable or a `data-control-` attribute, on the page or on one
  variant, and shows its value. The Controls tab adds the page's Seed, Clear, Reset, list toggles
  and worst-content toggle as built-in entries, Copy config, and Reset controls, which leaves the
  data alone. Opened from `file://`, the mockup draws the same controls in its own panel, top-right
  or, with the manifest's `placement`, top-left. A manifest with a default its control's field
  cannot hold, or two controls sharing an id, is refused whole, and a value a control cannot hold
  is never set.
- Every note carries `controls`, each manifest id with its value, and re-locating a note sets them
  again before the anchors run (`restored.controls`).
- The levels gain a `controls` dimension: `brief` or `everything`, shipped as `everything` at
  `standard` and `full`. New `reference/controls.md` says how to write the manifest, and the eval
  case `ed-controls-everything-default` checks it.
