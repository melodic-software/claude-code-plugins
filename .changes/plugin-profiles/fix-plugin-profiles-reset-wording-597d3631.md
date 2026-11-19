---
bump: patch
---

### Changed

- Reset asks about a moved repository's file as its own kind of question: Keep, then Put back, answered with `--keep-moved` and `--put-back-moved`; the folder-without-a-record flags no longer answer it, and the one question names files in a repository that moved among those it leaves to their own question.
- The profile skill's reset action shows every preview line exactly as printed before it asks anything, never a summary or paraphrase; its eval case fails a run that asks without them.
- The reset preview's line about files unchanged since an earlier reset names them: how many, the first three and how many more.
- Apply's preview in a repository that moved, while a record from before the move is kept, says in one line that reset puts the file back one layer per run, newest first, naming each such record and its profile.
