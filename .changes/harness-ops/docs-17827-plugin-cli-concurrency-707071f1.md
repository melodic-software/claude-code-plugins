---
bump: patch
---

### Changed

- `plugins` skill: the concurrent plugin CLI gotcha records the Claude Code 2.1.330 probe, where
  concurrent `claude plugin` writes lost no registry record, and names changelog item 2.1.330-027
  in its recheck trigger. The sweep stays serial.
