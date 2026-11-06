---
bump: patch
---

### Fixed

- presence-gate discovery and x in course-digest and video-digest

  course-digest's freshness check runs /discovery:explore and
  /discovery:research when the discovery plugin is installed, else
  explores and researches directly. video-digest's reply-chain harvest
  runs /x:read only when the x plugin is installed, else says the
  replies were not read.
