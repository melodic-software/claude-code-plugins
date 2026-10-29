---
bump: patch
---

### Changed

- Synced the shared `yaml-subset.awk` parser, which now refuses what `yaml-subset.mjs` refuses: a key repeated in one mapping (before, only under `-v STRICT=1`), an unknown backslash escape in a double-quoted string, a nested flow sequence such as `a: [[1, 2]]`, a `%` directive line (before, skipped), and a sequence-item map whose later keys sit more than two columns past the dash. A config file holding one of these is now a parse error, so `parse-concern-value.sh` takes the fallback for it, and `read-pre-ready.sh` fails closed on a key repeated inside a `pre_ready` item with that parse error.
