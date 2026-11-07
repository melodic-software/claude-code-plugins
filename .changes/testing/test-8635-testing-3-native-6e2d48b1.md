---
bump: patch
---

### Changed

- The run-e2e skill's legacy `evals.json` is retired into native `claude plugin eval` cases ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)):
  - 53 new cases (`e2e-*`), one per legacy entry. The narrated entries run with read-only tools: the scenario facts are in the prompt, and each case is graded on the reply. Entry 2 has no expectations list, so its llm grader quotes the expected output.
  - Entry 1 (`e2e-bare-prereq-gap`) is graded to the current skill text: with no scenario named and app-control not installed there is nothing to drive (run-e2e SKILL.md "Entry points"), so its legacy hard-fail gap report is not graded.
  - `e2e-mcp-server-no-ui` now ends "Use the `testing:run-e2e` skill if you have it." Unnamed, the skill fired in 0 of 1 runs.
  - Grader changes after the first smoke data. In each case the llm grader passed the reply, and every near-miss sample still fails:
    - `e2e-test-endpoint-refused`: also accepts "real UI".
    - `e2e-unknown-driver-defaulted`: also accepts "auto. Its source is the bundled default".
    - `e2e-workspace-none-collide`: also accepts "port 5173 may already be taken".
    - `hand-off-target` (`e2e-mask-hand-off-source-fails`, `e2e-mask-hand-off-none-source-publishes`): also accepts the path named inside the trusted root, "`.claude/skills/control-browser/SKILL.md` inside `/srv/trusted/shop`"; the checkout's copy still fails.
    - `e2e-hub-driver-wins`: also accepts "playwright. It comes from the control skill's hub".
    - The three own-instance cases: also accept "is not reused" and "does not adopt it", and now also require the reply to name the case's own instance port (51877, or 49210 in `e2e-own-instance-auto-unattended`), so a reply about another app's port fails. `e2e-own-instance-auto-unattended` also accepts "doesn't reuse" or "does not reuse".
    - `e2e-worst-case-word-scenario`: also accepts the code-span "not the `worst-case` action".
    - `e2e-native-run-disabled`: also accepts "invocation refused (disableBundledSkills" when more reason text follows inside the parentheses.
  - Prompt fixes after the first smoke data, where both graders failed because of how the case was built:
    - `e2e-session-name-slug` keeps a blank line after the scenario. With the instructions appended on the same line, the run dropped "; rm -rf tmp" as an instruction.
    - Every narrated scenario now ends in a full stop before the appended instructions (the four `e2e-worst-case-*` cases, `e2e-affected-unattended-drive`, `e2e-config-layers-delegated`, `e2e-nothing-affected`, `e2e-summary-scan-hit`, and both `e2e-mask-hand-off-*` cases), so the instructions do not run on into the scenario's last sentence.
    - `e2e-worst-case-keep` and `e2e-worst-case-network` allow reading the skill's own files, since the graded `--keep` and report rules live in `context/worst-case.md` and a run barred from it could not reach them; the repository stays off-limits.
    - `e2e-every-entry-point` states that each entry point drove and passed, because the run would not invent results.
