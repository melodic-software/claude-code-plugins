---
bump: patch
---

### Changed

- Skill bodies point at the live upstream sections for facts they used to restate (subagent
  resume, the concurrent subagent limit, curl's `--globoff`) and drop restated detail beside the
  parent-contract records (the preload-miss debug log, a WebFetch error string). The `setup` skill
  and README no longer say `apply` writes only `docs/conventions/discovery.yaml`: on an explicit
  yes it also writes the convention-home region and the `.gitignore` line, as its step 5 and the
  script already did. No behavior change.
