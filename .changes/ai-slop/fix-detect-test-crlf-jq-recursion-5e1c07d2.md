---
bump: none
---

Test only: the CRLF jq shim in `detect.test.sh` refuses to re-enter itself, so a wrapper jq that resolves jq through PATH can no longer start processes without end.
