---
bump: patch
---

### Fixed

- The shell-check git hook now fails, naming the tool and saying the change was not fully checked, when sed fails while it turns ShellCheck's output into findings. A crashed sed used to leave no findings to block on and the commit passing.
