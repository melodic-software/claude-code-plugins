---
bump: patch
---

### Fixed

- `run-validity.py`'s `permission denials` check sets aside a denied compound Bash call whose only real work is under the run's own plugin-data directory when its other commands are an `echo` with no redirect or command substitution, as in `rm -f '<data>/f'; echo "rm exit=$?"`, or a `curl` fetch into that directory whose `-o` file a later allowed Bash call names; without that retry the fetch still counts (#8635).
