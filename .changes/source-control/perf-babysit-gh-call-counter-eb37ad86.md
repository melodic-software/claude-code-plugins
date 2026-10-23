---
bump: patch
---

### Changed

- Every babysit script counts its gh invocations by token (`default`, or `override` for a call with its own `GH_TOKEN`) and endpoint kind (`graphql`, a REST method and route template with every value segment replaced by `{}`, or `gh <sub> <verb>`), and prints one `babysit-gh-calls` JSON line to stderr on exit, so a pr-merge job log carries each gate run's counts. A `--paginate` key is marked `+paginate`, since it counts invocations, not pages. Stdout and every decision are unchanged; a process that made no gh call prints nothing.
