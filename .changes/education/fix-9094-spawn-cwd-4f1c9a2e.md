---
bump: patch
---

### Security

- Shared `setup-apply.mjs` synced: it runs `git`, `bash`, `awk` and `diff` from the library's own directory and names the repository to `git` with `-C`, so on Windows, where Node looks for a bare command in the working directory before `PATH`, a same-named `.exe` or `.com` committed to the repository is never run. Without `--root` it still resolves the repository it is run from.
