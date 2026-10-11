---
type: llm
arm: both
---
PASS only if the answer names @quillkit/styled-core as the project's styling mechanism, follows the
pattern already in src/Card.tsx, and explicitly lists the questions it could not verify about the
library (for example how class names are scoped, whether media or hover queries are supported, how
`$space.m` style token references resolve) rather than stating them as facts. FAIL if it asserts
how the library works without marking any answer as unverified, or switches the banner to a
different styling approach without saying why.
