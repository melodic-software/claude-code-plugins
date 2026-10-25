---
bump: patch
---

### Security

- A size-split sub-issue a listed human last edited counts as that human's text only when every line after its header is one of its parent's trusted task-list lines or that line with its box ticked. GitHub names only the last editor, so a listed human ticking a box after another account's edit no longer makes that account's text trusted.
- pr-verify stops, writing no verdict, when a split sub-issue's native parent cannot be read or has more comments than the page it reads, instead of judging the pull request without the sub-issue's criteria. Before, an outsider could pad the parent past the page during a run and delete the padding before the merge gate counted the sub-issue.
