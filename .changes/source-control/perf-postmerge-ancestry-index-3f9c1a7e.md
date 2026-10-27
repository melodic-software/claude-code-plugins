---
bump: patch
---

### Changed

- `babysit_postmerge.py` answers whether a commit contains another from one `git rev-list --first-parent` of the local clone's copy of the branch when both commits are on that chain, and spawns `git merge-base --is-ancestor` only for a commit off it (reached through a merge's second parent, or absent). It reads the agent identity's pin comments for every judged merge 20 pull requests to a GraphQL query (`read_pins`), paging a pull request with more than 100 comments on its own. Verdicts are unchanged: an edited pin is still no pin, and a pull request the batch leaves out, or any failed read, still makes the verdict unreadable.
