---
bump: minor
---

### Added

- `/wizard:generate` library: `gate "Question?" "what is unchanged if you stop"` asks a yes-or-no question and ends the wizard with that message on anything but a yes, and `on_exit FUNC` registers a function that runs, with the exit status, when the wizard ends. The library now traps INT, TERM and HUP (exit 130, 143, 129), so Ctrl-C runs the handlers and the `write_env` temp-file cleanup too.
- `/wizard:generate` skill: a Kind column (browser, cli, local) in the stage plan, stage-code rows for non-browser stages, and Phase 3 checks that `TOTAL_STAGES` matches the stage count, that no `confirm` stands as a bare statement, and that the banner and closing text fit what the wizard does.

### Changed

- `banner "Title" ["intro line" ...]` takes its intro lines as arguments. With none, it prints a neutral default that mentions no browser and no saved answers, and a one-stage wizard prints "1 stage".
- `finish ["Title"]` takes a title (default "Done") and adds ", with items left to do by hand" when something was skipped, in place of the fixed "Setup complete". It also warns when the number of `stage` calls differs from `TOTAL_STAGES`.
- Printed strings in the template no longer contain em dashes.
- The re-run Gotcha says the pre-filled defaults apply only to values captured with `ask*` and `write_env`.
