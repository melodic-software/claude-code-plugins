---
bump: patch
---

### Changed

- **`explore-directions` adds three steps.** With no direction named and no host page fixing the
  look, it offers an optional reference pass before building variants. When `/playwright:playwright`
  is available, it screenshots every variant and uses its main control once before the handover.
  The handover states each variant's strengths and costs and recommends one; the user still picks.
- **The two skills, the shared discipline and the README are rewritten and restructured.**
  `explore-directions/SKILL.md`, `pressure-test/SKILL.md`, `context/discipline.md` and `README.md`
  were reorganized and reworded away from the upstream prototype skill they parallel. A five-word
  run scan against that upstream finds one shared run per file, the trigger label "what should this
  look like", and no shared run of eight words or more. The description's example triggers are now
  'how should this screen be laid out' and 'show me layout options'.
  `explore-directions` now picks its host from one intent-selector table (sub-shape A, sub-shape B,
  the HTML mockup substrate, the design canvas, each with its cleanup). Step 2 sorts design choices
  into must-differ and must-match rows; every variant must still be structurally different and
  visually distinct. Sub-shape B now requires a candidate-page check first. The switcher is
  specified as a table whose label row shows the key plus a descriptive name if exported. The
  handover lists its parts in order, and the skill runs five steps instead of six. Its examples use
  a shipment-tracking page, and its description reads "a few structurally different layouts (three
  by default) behind one route, toggled from a floating switcher". `pressure-test` also runs five
  steps: the language choice joins the logic-module step, which splits module from shell in a
  table and picks the module's form by who holds the state between calls, and the one-command
  start joins the TUI step. Its description's example triggers now include 'what happens if a
  refund arrives after the order ships' and 'which arguments should this call take'. Its HTML demo
  shell merges the state panel and free-play buttons into one region and points at step 2 for the
  module's placement. The user's remarks while driving are sorted into findings and missing states.
  Its examples use library loans. The discipline groups its six rules by who each serves and shows
  each one broken, keeping the rule names and numbers other text cites (3 and 6).
  Anti-patterns are tables of `/shipments` and library-loan cases; in `explore-directions` they
  are ordered by cost. The rules, labels,
  reply-template fields and steps keep their meaning; `docs/native-surfaces` quotes the new layout
  wording of the description.
