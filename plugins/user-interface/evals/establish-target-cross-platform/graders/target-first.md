---
type: llm
arm: both
---
PASS only if the answer establishes the target before or alongside the design: it asks, or states
its assumption about, which operating systems, shells and terminals the banner must work in,
covers Windows consoles or PowerShell as well as macOS and Linux, and gives a fallback (plain ASCII
frame, no color) for terminals without box drawing, color or UTF-8. FAIL if it designs for one
platform with no word on the others or no fallback.
