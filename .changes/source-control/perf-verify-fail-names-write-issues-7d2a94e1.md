---
bump: patch
---

### Fixed

- The pr-merge gate's verdict reader (`babysit_verify_evidence`) compares the number of a name that starts like a FAIL's but is no verdict name as text, so any length of digits is read without raising, and a number over 10 digits never counts toward the cap. pr-verify now writes the FAIL names with `-i` and the verdict's issues that 2.13.1 described as not written yet.
