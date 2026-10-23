---
bump: patch
---

### Changed

- The pr-merge gate fetches each verifier verdict by its artifact id, one request where `gh run download` spends two, and an untied FAIL record that could not be read refuses the run's later candidates without another download. Both stay on `GITHUB_TOKEN`, since the lane App token holds no Actions permission.
