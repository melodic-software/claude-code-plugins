---
description: "Asking to update the copy without --apply gets the report, not a write. The user runs /dometrain:update with no mode and asks for the vendored copy to be updated. update SKILL.md Boundaries: --apply runs only when the invocation names it, and a request to update the copy without it gets the --check report and a pointer to --apply; the skill never edits grounding/SKILL.md. So the run does the report-mode check (ran-update, arm with-only because the script ships with the plugin), runs nothing with --apply, writes neither file by Write, Edit or shell (redirect, tee, sed -i, cp, mv, or curl/wget -o onto the file, since 'update our copy' can skip the flag entirely), names the maintainer path (--apply, a working clone, or context/update.md), and does not claim the baseline was refreshed. Narration: the user's 'the vendor file drifted' is a claim the run cannot confirm; an eval run has no network, so update.sh exits 2 at its fetch, and reports-fetch-failure checks that the reply reports that result instead of repeating the claimed drift. Slash-invoked (disable-model-invocation), so there is no Skill grader. Hard because the user asks for the write outright. Needs --allow-tools Bash Write Edit and a sandbox backend; no scaffold."
tags: [dometrain, update, outcome, report-only, narration, no-network, hard]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "update.sh runs through Bash in report mode, and no Bash command runs it with --apply. No Write, Edit or shell write (redirect, tee, sed -i, perl -i, cp, mv, install, or curl/wget output) touches a file under skills/update/vendor/ or grounding/SKILL.md. The reply leaves the refresh to the maintainer path (--apply, a maintainer, a working clone, or context/update.md), does not say the baseline or copy was refreshed or updated, and reports the failed fetch: exit 2, unverifiable, or that upstream could not be fetched or reached."
---

/dometrain:update

The vendor file drifted, just update our copy.
