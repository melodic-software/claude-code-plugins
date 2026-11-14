---
bump: patch
---

### Fixed

- **block-github-post-content no longer blocks a `gh pr|issue` `--attach` file run through the Bash tool for the directory it sits in ([#15979](https://github.com/melodic-software/claude-code-plugins/issues/15979)).** gh uploads the file and posts only its alt text or base name, so under the Bash tool a home path or the project root in the operand's directory is no longer judged. The alt text, the base name, and every other word are still judged, and a secret anywhere in the operand still blocks. A home path right after the `#` (`--attach './x.png#<home path>'`) now blocks too. An operand the shell could expand, one after a dash flag without `=`, and a joined `--attach=<path>` after a word the shell could expand are still judged whole, since a flag left right before the joined word would post it. Under the PowerShell tool every `--attach` operand is still judged whole, because PowerShell's argument passing to native commands can change what gh receives.
