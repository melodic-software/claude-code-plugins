---
bump: patch
---

### Changed

- `measure-invocation.sh validate` prints one WARN per probe file naming every competitor that is
  not from the file's own plugin, and one INFO line giving the total and the reason, in place of a
  WARN per competitor. It drops each skill's `listing` and query-split INFO lines from the default
  output. `--verbose` restores both, byte for byte. The warning count, exit codes and every other
  WARN, FAIL and INFO line are unchanged. Over this repository's 67 probe directories, default
  stderr falls from 214,393 to 57,595 bytes.
