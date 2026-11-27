---
bump: minor
---

### Added

- The comment lint, `/code-tidying:remove-comments` scope and the comment census also judge `.awk`, `.cc`, `.css`, `.scss`, `.html`, `.htm`, `.xml`, `.editorconfig`, `.jsonc` (read as JSON), `.kt` and `.psd1` (read as PowerShell) files, and extensionless scripts whose first line is an sh, bash, dash, zsh, node or python3 shebang (`scripts/code-shebang.ere`). A consumer that wants a type left out lists it in `comment_lint_exclude`. `change-shape.py` and `commented-out-code.py` have no grammar for these types, so a deletion there is a proposal.
- `stylelint-disable`/`stylelint-enable` (with `-next-line` and `-line`) and `sourceMappingURL` or `sourceURL` comments are directives the lint keeps.

### Fixed

- An upper-case extension such as `.CSS` gets its lexer instead of being skipped.
- A regular expression literal after `=>` in JavaScript and TypeScript, and the pattern after `=~` in a Bash `[[ ]]`, are no longer read as comments, and neither is the code after them.
- A generated-file marker counts only on a comment line or at the start of a line (a docstring or block comment body), so a description, string or JSON value that mentions `@generated` or `DO NOT EDIT` no longer skips a hand-written file.
- `cr_is_code_file` reads the shared `scripts/code-extensions.txt` instead of its own list, `cr_comment_text` reads `<!-- -->` comments, and a remove-comments audit of a directory skips everything under a `.git` folder.
