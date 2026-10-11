---
type: llm
arm: both
---
PASS only if the answer states that this project has no design tokens, CSS custom properties or
design system to draw values from. FAIL if it never says so, or if it says or implies the project
already has tokens or variables it reused.

Examples:
- PASS: "The page has no CSS variables or design tokens, so every value below is my default."
- PASS: "styles.css defines no custom properties, so these are defaults."
- FAIL: "No need to add new tokens; I reused your existing variables."
- FAIL: "Here is the CSS for .plan-card."
