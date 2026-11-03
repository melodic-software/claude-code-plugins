# 3.1.5 Security scan evaluation (MANDATORY)

Part of [Phase 3: Monitor](monitor.md), which lists every section's file; a bare § number names a section listed there.

**Security scan results are ALWAYS blocking. They must be evaluated before merge, regardless of PR type.** This covers any actor performing security scanning: check-run names containing "security", "guardian", "CodeQL", "Snyk", "Dependabot", or similar, and bot comments about secrets or vulnerabilities.

**Discovery, not hardcoding:** security tools change. Any check run or bot comment reporting a security finding triggers mandatory triage, whether or not the tool is in a known list.

For each security finding:

1. **Read the full PR comment:** scanners post finding details (secret type, file, commit SHA)
2. **Read the check-run details:** the PR's checks list with name, state and bucket ([GitHub](../../../reference/providers/github/pull-request/readiness.md#gate-1-list-the-checks))
3. **Classify each finding:**
   - **True positive** (actual secret leaked / real vulnerability) → BLOCK merge. Remove the secret, rotate credentials, then push a fix. Route through the 3.2 research-driven fix cycle
   - **False positive** (code examples, test fixtures, documentation) → document the rationale, and note that the repo owner should dismiss it in the scanning tool's UI/dashboard or its ignore config
   - **Not applicable** → document why
4. **Every finding must have an explicit classification.** No unclassified findings before merge

**When a security check run shows `FAILURE`:** the PR is not necessarily broken; the scanner found something to evaluate. The failure is the *trigger* for triage, not an automatic merge block. After classification, include the disposition in the readiness verdict (Gate 3 in [readiness.md](readiness.md)).
