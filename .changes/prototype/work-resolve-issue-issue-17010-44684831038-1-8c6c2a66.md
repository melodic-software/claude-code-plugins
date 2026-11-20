---
bump: minor
---

### Changed

- Re-locating a note now tells a removed control from a page that marks none. When the page marks
  no data control or has no controls runtime, the part is left out of `restored` and listed in the
  result's new `unmarked` field, where it used to read false like a control the page lost ([#17010](https://github.com/melodic-software/claude-code-plugins/issues/17010)).
- A region note over content with no test ids now records the elements it covers: when the region
  crosses no test-id element, `elements` lists the holding element's children it crosses. The note
  schema's `x-version` moves to 5, and the host page's note summary says "element(s)", not "marked
  element(s)".
