---
bump: patch
---

### Changed

- The README no longer spells out Go's generated-code marker or what `goimports` knows about
  it; the skip-generated-files rule and the header-before-marker case stay, with a pointer to the
  `go generate` section.
- The `goimports` requirement no longer carries the install command or the toolchain and
  `GOPATH` notes. It keeps that `goimports` must be on `PATH`, is never downloaded, and that the
  batch row skips and the SessionStart probe reports when it is absent, with a pointer to the
  `goimports` docs.
