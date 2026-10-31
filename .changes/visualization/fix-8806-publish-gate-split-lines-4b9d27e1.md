---
bump: patch
---

### Fixed

- The publish gate now catches a credential that a line break splits in two: it also reads each pair of adjacent lines joined, raw and normalized. The OpenAI key, the R2 key pair and the password or secret assignment patterns still read one line at a time, so an `sk-` word ending a line or an md5 line above a sha256 line raises nothing. Machine paths and hostnames are still read one line at a time.
