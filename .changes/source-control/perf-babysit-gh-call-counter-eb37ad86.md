---
bump: patch
---

### Changed

- Every babysit script counts its gh invocations by token (`default`, or `override` for a call with its own `GH_TOKEN`) and endpoint kind (`graphql`, a REST method and route template that keeps only the REST route words the scripts call and logs every other segment, an owner, branch or path included, as `{}`, or `gh <sub> <verb>`), and prints one `babysit-gh-calls` JSON line to stderr on exit, so a pr-merge job log carries each gate run's counts. A `--paginate` key is marked `+paginate`, since it counts invocations, not pages. Stdout and every decision are unchanged; a process that made no gh call prints nothing.
