---
bump: minor
---

### Added

- `/user-interface:write-css`: writes and reviews CSS with modern, self-adapting techniques, after
  reading the project's own design system, stack, browser targets and lint config. Its 47
  techniques, grouped by topic, come from vojtaholik/good-css at `b645ab15b9fc`; review mode runs
  that project's `check-css.mjs`, vendored unmodified under `skills/write-css/vendor/`. Credits per
  technique are in `docs/upstream/good-css.md`.
- `scripts/check-good-css-drift.sh --check`: weekly drift check of the upstream files the skill
  absorbed or vendors (`scripts/check-css.mjs`, `LICENSE`, `PRACTICES.md`) and of the vendored
  copies. Exit 0 no drift, 1 drift, 2 unverifiable.
- **Notice.** The technique text in `skills/write-css/reference/` and the vendored linter carry
  material from vojtaholik/good-css (MIT). This paragraph travels with them, is the copy that ships
  with the installed plugin, and must survive any future trim of this changelog:

  ```text
  Copyright (c) 2026 Vojta Holik

  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
  associated documentation files (the "Software"), to deal in the Software without restriction,
  including without limitation the rights to use, copy, modify, merge, publish, distribute,
  sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all copies or
  substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
  NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
  DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ```
