---
bump: patch
---

### Fixed

- The leak scan the lane telemetry body gate runs now also reads JSON-encoded text with its `\n`, `\r` and `\t` escapes decoded, so a credential at the start of a line or after a tab in a JSON body is withheld. Before, the escape's letter sat directly before the token and hid it from every pattern anchored on a word boundary (#12562).
