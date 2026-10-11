---
bump: patch
---

### Changed

- The `Brain Fried` output style now matches the built-in styles in the `/config` picker: its
  name is title case and its description says what Claude does. The saved `outputStyle` value
  is case-sensitive, so if you had selected `Brain fried`, select `Brain Fried` again in
  `/config` or with `/output-style`; until then the session falls back to the default style.
