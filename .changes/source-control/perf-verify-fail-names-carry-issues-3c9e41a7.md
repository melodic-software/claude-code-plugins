---
bump: patch
---

### Changed

- The pr-merge gate's verdict reader (`babysit_verify_evidence`) accepts a pr-verify FAIL artifact name that ends with `-i` and the numbers of the issues its verdict records, ascending, each once, joined by dots (at most 10). The cross-pull-request repeated-fail cap counts every counted FAIL whose name carries one of the pull request's closing issues, read from the artifact listing the gate already holds, so it adds no request. A name without the issues keeps today's rule. A PASS or PASS-NOTES name that carries issues, or issues out of order or repeated, is no verdict name, here and in the merge-skip key (`babysit_merge_skip`), and neither is a pull request number over 10 digits or a name over 194 characters. A name that starts like a FAIL's (any digits for the number) but is no verdict name holds (`verify:unreadable`) when its run is of verifier origin, or is tied to the pull request and cannot be read, rather than being skipped; it costs one run read, shared by the run's gate processes through the run cache. Deleting such an artifact clears the hold. Its number is compared as text, so any length of digits is read without raising. pr-verify does not write these names yet.
