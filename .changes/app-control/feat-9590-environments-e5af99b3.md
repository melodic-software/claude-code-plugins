---
bump: minor
---

### Added

- The control-skill contract gains an "Environments" section. Environment entries (`url`, dependency `services`, `extends`, a `writes` policy per write of `never`, `attended` or `unattended`, and `production: true`) come only from `config/defaults.json` committed at HEAD. The local, environment-variable and flag layers may select an environment by name, never add or redefine one; the driver CLI refuses such a layer with exit 4. An entry that extends a production entry stays production.
- The contract gains an "Integrated apps" section: a system whose pages a journey crosses, such as a separate identity server, gets its own control skill, and its steps are included by reference as `<app>:<path>`. The `checkouts.<app>` setting holds the path of another repository's local checkout; when it is unset or wrong, the run stops before launching and names the setting and the repository to clone. Committed config pins each such app by commit SHA in `pins.<app>`; the run stops before launching unless the checkout holds that commit and its control skill folder matches it with no untracked files, and that app's config and floors are read at the pin. An included `cli:` step runs the owning app's `cli/` with that app's config and credentials.
- A new Write grants floor: every write command takes `--step <id>`, the step's unprefixed id (or the command name without a steps file), looked up in the committed `writes`; a missing key, an unlisted one, `never`, or `attended` without `--attended` exits 4.
- `<environment url>` and `<<service> service url>` placeholders in Launch and Ready are filled as one argument, validated as an http(s) URL, and run without a shell.
- The Production floor now states that `--yes` needs `--attended`, so no config turns on an unattended production write. Writes to environments not marked production keep their current rules.
- `## Capture` can hold one row per tier (such as browser and server). `/app-control:drive capture` records each tier's row with its own tool, and the tier is part of the artifact name.
- `/app-control:drive ready` checks each dependency service of the selected environment: that it answers, and, where the app shows its target, that the app sends to it. `report.json`'s `ready` gains `environment` and `services`.
- `/app-control:map create` asks for each related system's repository and for which environment is production. It writes environment entries and an Integrated apps hub line, and it never writes into another checkout.
