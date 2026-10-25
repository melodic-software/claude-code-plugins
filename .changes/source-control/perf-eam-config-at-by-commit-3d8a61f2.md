---
bump: patch
---

### Changed

- The pr-merge gate and the verifier reader read the pipeline config at a commit once per run: `babysit_merge_policy.config_at` saves each clean read in the run cache keyed by repository and commit, and both the default branch head's config (`with_default_branch`) and `babysit_verify_evidence.py evidence --base-sha` read through it. The default branch head itself is still read live once its two-minute window passes, so a moved head reads its new config; a read with an error or a note is never saved. Each later candidate whose base commit or default branch head was already read skips that read: local git reads where the `.base` clone holds the commit, two lane-token contents reads where it does not. The GITHUB_TOKEN reads, and the per-candidate artifact listing refresh, are unchanged.
