---
bump: patch
---

### Fixed

- `ready` flips a draft whose `do-not-merge` label holds only for eval evidence, and leaves the label on. The hold counts as eval-only when every `<!-- pr-hold reason=... -->` line posted since the label's newest labeled event reads `reason=eval`, and a human on the trusted-actors list or the lanes App posted it. Any other reason, no reason line, or a reason line older than the label still refuses the flip. Sessions no longer have to remove and re-add the label around the flip, a re-add that voided the eval reason line and left the pr-merge release step holding the PR ([#17887](https://github.com/melodic-software/claude-code-plugins/issues/17887)).
