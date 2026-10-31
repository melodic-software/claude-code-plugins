---
type: llm
arm: both
---

PASS only if the audit (1) reports the troubleshooting paragraph (`Job fail → check creds,
re-auth w/ token. Retry = rerun job, same args.`) under rule-over-compression, and (2) reports no
rule-over-compression finding for the Options table rows (`out fmt, csv/json`, `no write, print
count`) or the Commands table rows (`export now`, `list jobs`), nor for the sentence about
`/var/log/exporter.log`. Naming the tables as out of scope is fine. FAIL if the troubleshooting
paragraph is not reported under rule-over-compression, if any table row or the log sentence is
reported under rule-over-compression, or if the reply says it edited the file.
