---
bump: patch
---

### Security

- pr-verify's `resolve-pr.mjs` now checks who renamed a pull request's title before it uses the PR as its own spec, i.e. a trusted PR with no closing issue ([#9115](https://github.com/melodic-software/claude-code-plugins/issues/9115)). The title has to be never renamed, or last renamed by the PR author or a kind-human trusted actor. That is the rule the body's last editor already follows. When the title fails the check, the PR is not its own spec, the same result as an untrusted body edit. The rename read is `titleRenamers`, exported from `select-trusted-text.mjs` and shared with that action, which keeps its own rule: every renamer must be listed. In resolve-pr, a rename page that comes back with no node list is a failed read, so the title is never trusted on a misread. select-trusted-text now fails the same way on a rename or closing-issues page with no node list, where it used to read that page as empty.
