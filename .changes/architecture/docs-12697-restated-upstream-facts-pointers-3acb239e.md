---
bump: patch
---

### Changed

- `map-containers` and `map-context` no longer give mermaid's C4 status as the reason the
  dialect key refuses mermaid; the refusal, the unset key and the no-diagram fallback stay, with a
  pointer to the Mermaid C4 page.
- `map-landscape` no longer states what each dialect offers for a landscape view. It keeps that
  the mermaid output is a `C4Context` diagram without a focal system and points at the
  Structurizr `systemLandscape` view and the Mermaid C4 page.
