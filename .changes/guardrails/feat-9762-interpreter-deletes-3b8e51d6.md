---
bump: minor
---

### Added

- `block-root-delete-target` judges the code a `python -c`, `node -e`, `perl -e` or `ruby -e` runs, and a script such an interpreter reads from a heredoc or here-string. A call to its language's deleter (`shutil.rmtree`, `os.remove`, `fs.rmSync`, `FileUtils.rm_rf`, `File::Path` `rmtree` and their siblings) has its string-literal path judged the way a recursive `rm` operand is, so `shutil.rmtree('/')`, one aimed at `$HOME` and one outside the allowed roots are refused, and one strictly inside the git toplevel, the scratchpad or an allowed root passes. A deleter whose path is not a plain string literal (`shutil.rmtree(sys.argv[1])`) is refused, because the guard cannot place it. A command the code runs (`os.system`, `subprocess.run`, `child_process.execSync`, `system`, a backtick) is judged as the shell or the program would receive it. The mechanism named only inside quoted prose, such as a `git commit -m` message, stays allowed.
