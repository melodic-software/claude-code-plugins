---
bump: minor
---

### Added

- The monthly Task Scheduler run can start in a plugin profile: `setup schedule` asks for one, and the wrapper's `-PluginProfile <name>` asks plugin-profiles for the profile's launch command at each run, clears the variables it names from the run's environment without `env`, and passes its `--settings` before the audit's arguments. When plugin-profiles is missing or the launch refuses, the run does not start and the reason goes to the stderr log. With no profile the run is unchanged.
