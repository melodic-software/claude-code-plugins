---
bump: patch
---

### Fixed

- The interview `round.sh` CLI: `--dir` is accepted after every subcommand, as the help says; `status`, `lease`, `doctor` and `validate` take `--json` (the text output is unchanged); `round.sh` skips an interpreter below Python 3 and exits 2 with its missing-prerequisite message when none is left; `ensure-running --open` prints one stderr line when no browser opens; help carries examples and `apply --help` lists the op names.
