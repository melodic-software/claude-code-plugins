---
bump: major
---

### Removed

- The `lint-full` pre-push git-hook entry. At 11.8 s on a 44-file change it is over the check-placement convention's 3 s push budget, so `/source-control:pull-request` runs `git-hooks/lint-full.sh` in its pre-PR check instead. A lefthook remote stops running it on its next fetch; a local or shared copy an earlier `apply install-git-hooks` installed keeps running until you remove it.
