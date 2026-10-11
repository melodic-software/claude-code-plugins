---
bump: minor
---

### Changed

- **`/education:illustrate` page look ([#6171](https://github.com/melodic-software/claude-code-plugins/issues/6171)).** Diagram cards cycle through five accent colors in light and dark themes, so neighboring cards differ, and each card draws its diagram on a tinted area with the heading and caption outside it. The first card is the lead diagram, drawn larger. The "Still unclear" row is now a small `?` toggle in the corner of each card, still the same checkbox with a screen-reader name, so the copied `picked: diagrams-N` reply is unchanged. Every accent keeps node labels, card text and dates at 4.5:1 contrast or more, checked by the builder tests.
