---
bump: minor
---

### Added

- reuse-or-replace writes paved-path entries; lever-check gains a migration row

  /discipline:reuse-or-replace is now the one skill that writes paved-path
  entries. When work sets a new way for a recurring concern or openly
  replaces a listed one, it drafts the entry (concern, chosen way, enforcing
  check or none) and writes it only after you say yes. With no index row or
  file it offers to create both, and an unattended run only proposes. The
  lever check gains a migration row: a change that moves many sites to a new
  way uses an established codemod or structural-rewrite tool first, then a
  written script, then hand edits.
