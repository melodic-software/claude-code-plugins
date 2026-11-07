---
description: "Legacy clarify 3. History: the previous assistant message is the dense Round 4 (Q12 to Q15); the workspace and home hold no rendered-views setting, so the resolver prints a null medium and 'view: auto (plugin default)' (run by hand in an empty home with the option token passed literally in single quotes). The skill runs the resolver first (SKILL.md lines 83-97), prints its report line, and lets the rendering table pick the form (lines 103-117). The Artifact tool is off in eval runs, so the form is a local HTML file or terminal markdown. resolver-ran (with-only) needs the resolver call with --lane adhd:clarify; report-line the printed line; table-or-file a decision-table header in the reply or an HTML path handed back; no-artifact-claim fails a claimed publish; table-shape and form-from-table (llm, trace) quote legacy expectations 1-3 and 5. Watch: a Bash write to the OS temp directory may be denied in the sandbox, and the resolver needs a real node on PATH. UNVERIFIED: whether a run expands ${user_config.medium} in the skill text (SKILL.md lines 83-86); the command (line 89) takes --option '<option>', and the skill says to pass '' when the token reads empty or unsubstituted and never to put a ${user_config.*} string in the shell command. Needs --allow-tools Bash; a history_file case runs single-arm, so pass --ablation with-without."
tags: [adhd, clarify, outcome, rendered-view, history, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Bash]
expected_outcome: "The resolver runs with --lane adhd:clarify, the reply prints 'view: auto (plugin default)', and the decision table (numbered rows; Item back-links Q12-Q15; verbatim recommendation and alternative cells) is in the reply or in a local HTML file whose path the reply gives; no artifact is claimed."
---

/adhd:clarify
