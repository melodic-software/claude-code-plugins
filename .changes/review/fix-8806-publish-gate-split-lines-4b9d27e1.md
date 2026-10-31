---
bump: patch
---

### Fixed

- The publish gate now catches a credential that a line break splits in two: it also reads each pair of adjacent lines joined, raw and normalized. A password or secret assignment split across two lines is caught too. The OpenAI key and the R2 key pair patterns still read one line at a time, so an `sk-` word ending a line or an md5 line above a sha256 line raises nothing. Machine paths and hostnames are still read one line at a time.
