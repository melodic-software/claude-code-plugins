---
bump: minor
---

### Changed

- Shared interview page: carries the canonical chrome
  ([#12654](https://github.com/melodic-software/claude-code-plugins/issues/12654)). A person's own
  card offers its System/Light/Dark toggle, opening on System, as the page's only theme choice. The
  Discussion composer is its comment box, with the "Comment" heading and the "Your comment for the
  session" label. `app.css` carries the chrome's rules verbatim, and the new `test_page_chrome.py`
  checks them.

### Removed

- Shared interview page: the accent swatches, the palette buttons (Midnight, Slate, Paper, High
  contrast) and the owner's "Default theme for everyone" setting, with their styles. The page and
  the prototype page now paint only the mode a person picked. A session saved with a `theme` setting,
  or `accent` and `palette` prefs, still loads. The `shared_session.accent` key is retired: it has
  no effect, and a file that still sets it stays valid. `ui_contrast.js` and `ui_layout.js` now
  check dark and light only, and `ui_surfaces.js` checks that no accent or palette picker renders.
