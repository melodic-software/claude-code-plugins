---
bump: patch
---

### Fixed

- **`research-sweep` holds `applies_to` to the grammar criterion 13 parses.** Every `applies_to`
  field in the read, consolidate and synthesis schemas now carries the grammar as a `pattern`, and
  the workflow checks each surviving finding and source against the same grammar as
  `check-source-applicability.py`. For a free-text value, the workflow asks the synthesizer once
  more and names the grammar. A value that still fails is recorded `unstated`, and its text goes to
  the finding's qualifiers, so free text no longer reaches the artifact.
