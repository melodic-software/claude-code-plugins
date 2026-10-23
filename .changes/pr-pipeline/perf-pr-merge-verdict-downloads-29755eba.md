---
bump: patch
---

### Changed

- The pr-merge gate fetches each verifier verdict by its artifact id, one request where `gh run download` spends two, and a verdict download refused for a rate limit under `GITHUB_TOKEN` is made again with the lane App token, which also moves the run's later downloads to it, as the review-evidence reads already do. Once the lane App token is refused a download for another reason (it holds no Actions permission), the run's later downloads stay on `GITHUB_TOKEN`. No gate decision changes.
