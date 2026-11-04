---
bump: minor
---

### Changed

- **The config cascade's personal layer is called the personal override.** `scripts/resolve-config.sh` names it `personal-override` where it printed `overlay`: in the `paths` and `layers` output, the `!inert:` lines, the `_layer` stamp on a tier from `docs-naming.local.yaml`, and its error messages. `/docs-naming:setup check` prints the rows `layer personal-override`, `old personal override file` and `personal override ignored`. The setup skill, README, `reference/config.md` and `retirements.yaml` use the same name. Which file is read and how layers merge are unchanged ([#13190](https://github.com/melodic-software/claude-code-plugins/issues/13190)).
