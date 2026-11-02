---
bump: minor
---

### Changed

- apply-patch's `ci-context` row (fix-ci) and `review-threads` row (address-feedback) refuse a patch that changes a `.gitattributes` file at any depth, anything under `.husky/` or the root `lefthook.yml`, in any case and through any `..` segment, a rename onto one included. Each changes what git, or a hook it runs, does on the next checkout or commit. The three new optional refusals are `gitattributes`, `husky` and `lefthook`; no other row names them, and the `issue` row is unchanged.
