---
bump: patch
---

### Fixed

- The `pt-vendor-fit-no-sandbox-key` eval case no longer fails a run that sets `PINGLY_LIVE_KEY`
  to a dummy value to show the adapter refusing a production key, or that unsets it before
  running the shell: its `no-live-key-bash` grader now fails only a Bash call that reads the
  variable. Two new graders fail a written or edited file that reads the key from the environment
  (`os.environ`, `os.getenv`), which the Bash grader could not see.
