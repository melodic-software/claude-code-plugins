---
bump: patch
---

### Fixed

- name each skill's templates from the plugin root

  plan, interview and questionnaire now name each template they copy as
  ${CLAUDE_PLUGIN_ROOT}/skills/<skill>/templates/<file>. A bare
  templates/<file> was read from the plugin root, where no such file
  exists, so the read failed; in an eval sandbox it was denied, which
  made the run INVALID.
