---
bump: patch
---

### Fixed

- **block-github-post-content no longer blocks a `gh pr|issue` `--attach` file for the directory it sits in ([#15979](https://github.com/melodic-software/claude-code-plugins/issues/15979)).** gh uploads the file and posts only its alt text or base name, so a home path or the project root in the operand's directory is no longer judged. The alt text, the base name, and every other word are still judged, and a secret anywhere in the operand still blocks. A home path right after the `#` (`--attach './x.png#<home path>'`) now blocks too. An operand the shell could expand, one after a dash flag without `=`, and a joined `--attach=<path>` after a word the shell could expand (on PowerShell, also an empty word) are still judged whole, since a flag left right before the joined word would post it. On PowerShell, every `--attach` operand of a command in which any word holds a double quote is judged whole too, since legacy native argument passing does not escape the quote and the words can split or join.
