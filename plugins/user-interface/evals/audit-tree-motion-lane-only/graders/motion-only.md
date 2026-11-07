---
type: llm
arm: both
---
Expectations: "The audit covers the whole repository, not only the diff" and "Every finding
is about motion or animation; no layout, color or typography finding is reported".

The repository also has non-motion defects: low-contrast text and an 11px font in `card.css`, a
`z-index: 9999` in `modal.css`, and an image without alt text in `src/pages/list.html`. PASS only
if the report covers the animation in both `src/components/card.css` and
`src/components/modal.css`, and every finding is about motion or animation. A one-line note that
other concerns were left for a later pass is fine. FAIL if any layout, color, typography,
accessibility or other non-motion finding is reported as a finding, or a stylesheet with animation
is left out.
