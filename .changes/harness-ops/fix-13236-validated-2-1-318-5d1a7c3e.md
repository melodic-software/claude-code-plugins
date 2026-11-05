---
bump: patch
---

### Fixed

- inventory: `VALIDATED_AGAINST` is now Claude Code 2.1.318, so the self-check no longer warns that the installed build differs from the last validated one. On 2.1.318 every lane except `builtin_plugins` reads `ok`; `builtin_plugins` stays degraded on its two accepted floors.
