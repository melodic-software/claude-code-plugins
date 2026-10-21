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

- review plugin manifests by their parsed change instead of the blanket floor

  A `plugins/<plugin>/.claude-plugin/plugin.json` or the top-level
  `.claude-plugin/marketplace.json` no longer takes the `**/.claude-plugin/**`
  hold. `babysit_risk.score` compares its base and head JSON against
  allow-lists and rates any other difference HIGH as
  `manifest-review-required`, so an unlisted key such as `skills`, `commands`
  or `name` fails closed. In `plugin.json` only `version`, `description`,
  `keywords`, `author`, `homepage`, `repository` and `license` may differ,
  and `version` may not be removed; an existing `userConfig` entry may
  change only its `title` or `description`, and an added or removed entry
  holds, as does a `defaultEnabled` change. In `marketplace.json` only `plugins` and `metadata.description` or
  `metadata.version` may differ; an existing plugin entry may change only
  its version, description, keywords, author, homepage, repository, license,
  category and tags, and an added, removed or renamed entry holds. A new
  `plugin.json`, or a side that cannot be read, does not parse or repeats a
  key, holds. Any other file under `.claude-plugin/`, eval stub manifests
  included, still holds.

- hold eval cases that run a scaffold script

  A changed file in a directory from `plugins/<plugin>/evals/` down to its
  own whose `case.yaml`, at the base or on either side of the diff, could
  name a `context.scaffold_script` rates HIGH as
  `eval-scaffold-review-required`, because `--scaffold` runs that script
  outside the sandbox. The merge wrapper reads those case files at the base
  only when such a path changes; an unread or unparsable case file holds.
  The base readers now also refuse a base or head that is not a commit SHA.
