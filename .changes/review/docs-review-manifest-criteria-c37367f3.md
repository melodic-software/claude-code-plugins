---
bump: minor
---

### Added

- `/review:code-review` checks a `plugin.json` or `marketplace.json` change for a stated reason
  behind a changed or removed `userConfig` default, the client floor a new `options` list raises,
  a new setting's default and its reader, the bump level, and whether the description and
  marketplace entry match what ships.
- `/review:security-review` flags a guard default turned off, and names every added hook, server,
  monitor, dependency or marketplace source with what runs and where it comes from.
- Both lanes write one `manifest <field>: pass` or `flag` line per manifest item in the summary.
