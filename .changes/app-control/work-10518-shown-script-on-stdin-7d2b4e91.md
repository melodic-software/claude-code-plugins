---
bump: patch
---

### Fixed

- **An elevated capture runs the script text the person saw, never the file the builder wrote** ([#10518](https://github.com/melodic-software/claude-code-plugins/issues/10518)). After the yes, `/app-control:drive` feeds the builder's printed output to `sh -s` in a quoted heredoc. A process running as the person's uid could rewrite the written file between the display and the run. `build_capture_script.py` now prints its process lines as shell comments, so its whole output is the script. With `--elevate` it writes the file as a mode 0600 record that nothing runs. The script body is one group with stdin from `/dev/null`, so the shell reads all of it before it runs any of it, and a recorder that reads stdin cannot read the rest of the script. A script built without `--elevate` still runs from its 0700 file. The builder now refuses an unprintable character, such as a bidi override, in `--write`, `--capture` or a recorder argument, where it would make the shown text read differently from what runs. `pid-binding.md` states the residual limit: a process with the person's uid can still act as that person in other ways.
