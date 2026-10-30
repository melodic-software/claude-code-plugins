---
bump: patch
---

### Changed

- pr-feedback-dispatch.yml and pr-unblock-dispatch.yml restore the artifact listing pr-merge's last
  scheduled or hand-started run on main saved (`listing-carry.mjs`, its provenance checks unchanged)
  and set `BABYSIT_VERIFY_LISTING` and `BABYSIT_VERIFY_LISTING_CARRY` for the FAIL-cap reader, as
  pr-merge.yml's gate does. The first pull request's read lists only the pages since the carried
  listing, and later ones reuse or extend the job's saved listing, instead of each read listing every
  artifact of the repository. A listing that does not hold GitHub's live artifact count is still
  dropped for a full read.
