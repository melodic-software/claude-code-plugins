---
bump: patch
---

### Fixed

- The pr-merge gate's Dependabot content rule, and its fix-scope check on a lanes App fix, count a manifest directory as covered only when `.github/dependabot.yml` lists its ecosystem and directory at both the base and the default branch head. Its review-only match reads the Dependabot policy at both too: an entry either side lists matches, and either side unreadable makes the policy unreadable. A tightening on main now reaches Dependabot pull requests opened before it.
