---
bump: minor
---

### Added

- `/review:code-review` checks a `plugin.json` or `marketplace.json` change for a stated reason
  behind a changed or removed `userConfig` default, the client floor a new `options` list raises,
  a new setting's default and its reader, the bump level, and whether the description and
  marketplace entry match what ships.
- `/review:security-review` flags a `userConfig` default change that widens what a guard allows
  (judged by the code or skill text that reads the key) or adds a guard with a permissive
  default, and flags every other changed manifest field outside a small inert set of display
  text and a changed version, naming what runs
  and where it comes from.
- Both lanes write one `manifest <field>: pass` or `flag` line per manifest item in the summary.
