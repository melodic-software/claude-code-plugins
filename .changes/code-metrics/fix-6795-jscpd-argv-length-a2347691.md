---
bump: patch
---

### Fixed

- audit-duplication: the jscpd adapter no longer puts the lane's file list on jscpd's command line. It writes the files to the `path` array of a temporary config file and passes `--config`, so the command line stays the same length for any lane and a large Bash lane on Windows reports its clone classes instead of failing with exit 3 and empty stderr. The lane is still one jscpd run, so clones across distant files are still found. When jscpd writes no report, the exit-3 message now names jscpd's exit code. Passing `--config` stops jscpd's own `.jscpd.json` discovery, so a consumer `.jscpd.json` no longer reaches the scan. jscpd 5.x also ignores a `package.json` `jscpd` key; 4.x still applies the keys code-metrics does not set.
