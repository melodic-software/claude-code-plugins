---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: in an incremental review chain, the merge gate takes the CRITICAL count of an earlier review's summary findings from that review's own `critical-findings:` line. It reads the line from the review's reviewed-head marker, or from a summary comment posted while that review's job ran. An earlier review that reported findings with `critical-findings: 0` no longer holds the pull request on `security-finding`. Those findings still count as open until a new head or a person clears them. An earlier review without exactly one such line still counts all its summary findings as CRITICAL.
