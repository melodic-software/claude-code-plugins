---
description: 'Legacy audit 9. The operator audited another repository this morning and asks whether report here serves those findings or an audit here clobbers them: neither, because the path carries the <repo-identity>/<worktree-discriminator> key the resolver prints, the data directory is one per plugin per machine, and report reads the file back. runs-resolver reads the trace and names-key-scheme the reply. Bash is granted because the resolver is a script. Hard because an unkeyed file looks harmless until it is read back.'
tags: [audit, harness-memory, report, keying, hard]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The run executes lib/state-key.sh; the reply says the two projects read and write under different <repo-identity>/<worktree-discriminator> keys beneath the plugin data directory, so report here never serves the other repo''s findings and an audit here does not overwrite them; it names the read-back as why keying is required (an append-only history would not fix a wrong report served) and says two worktrees of one repository key apart too.'
---

/harness-memory:audit I ran this audit in my work repo this morning. I am now in a completely different repo on the same laptop. If I run `report`, whose findings do I get, and if I run the audit here, does it clobber this morning's? Don't change any files, and don't list the plugin data directory yourself: answer from what the skill's scripts print. No one is around to answer questions while this runs, so put the answer in your reply.
