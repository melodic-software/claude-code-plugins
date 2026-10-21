---
bump: minor
---

### Added

- exempt two narrow change classes from the HIGH path floor

  `babysit_risk.score` no longer gives a modified
  `plugins/<plugin>/skills/<skill>/SKILL.md` the `high-capability` hold when
  its head text is its base text with the one line
  `disable-model-invocation: true` added as a new frontmatter key, unless an
  agent definition at the base or changed in the diff could preload the
  skill (its `skills` entry names the skill's directory or `name`, or it
  cannot be read). The merge wrapper reads the base's agent definitions only
  for such a change; when they cannot be read the hold stays. A non-script
  file whose every path is under `plugins/<plugin>/evals/` (case-sensitive,
  safe, not `*.sh`, `*.py`, `*.mjs`, `*.js`, `*.ps1` or `*.cjs`, not mode
  100755, under no declared path) takes no capability hold and none from the
  `plugins/review/**`, `plugins/guardrails/**`, `plugins/work-items/**` or
  `plugins/**/scripts/**` floor entries unless a `denied-paths` glob repeats
  one. Manifests, named files such as `CLAUDE.md` and `.claude/**`, and
  every other floor entry still hold.
