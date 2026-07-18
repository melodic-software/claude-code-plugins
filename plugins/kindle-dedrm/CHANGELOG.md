# Changelog

All notable changes to the `kindle-dedrm` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Changed

- **`gh` CLI declared and its absence handled** (prerequisite-visibility
  wave). The README Requirements now name the authenticated `gh` CLI; the
  setup workflow's DeDRM_tools download step falls back to the pinned tag from
  `references/versions.md` when `gh` is unavailable or returns nothing,
  instead of composing a malformed URL. The Key_Finder URL resolution gained
  the same empty-match guard (stop with the mirror-procedure pointer rather
  than feeding `curl` an empty URL).

## [0.2.0]

First versioned release covered by this changelog; see the git history of
`plugins/kindle-dedrm/` for earlier changes.
