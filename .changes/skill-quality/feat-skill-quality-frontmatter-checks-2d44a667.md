---
bump: minor
---

### Changed

- `check-skill.sh` check 12 now exempts `disable-model-invocation: true` skills from requiring `Use when:` phrasing, warns when they carry trigger phrasing or exceed 150 chars, and check 3 skips `disable-model-invocation: true` skills while downgrading lexically covered trigger drops to `INFO`.
- Slimmed `/skill-quality:setup` description to a 147-char one-line summary and removed `skill-quality:setup` from `probes/check.json` competitors.

### Fixed

- `measure-invocation.sh` warns in `validate` and skips `disable-model-invocation: true` competitors in `score` so user-only skills never compete in model auto-invocation.
