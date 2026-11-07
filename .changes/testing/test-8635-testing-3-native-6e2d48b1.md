---
bump: patch
---

### Changed

- The run-e2e skill's legacy `evals.json` is retired into native `claude plugin eval` cases ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)):
  - 51 new cases (`e2e-*`), one per legacy entry. The narrated entries run with read-only tools: the scenario facts are in the prompt, and each case is graded on the reply. Entries 1 and 2 have no expectations list, so their llm graders quote the expected output.
  - `e2e-mcp-server-no-ui` now ends "Use the `testing:run-e2e` skill if you have it." Unnamed, the skill fired in 0 of 1 runs.
  - Grader changes after the first smoke data. In each case the llm grader passed the reply, and every near-miss sample still fails:
    - `e2e-test-endpoint-refused`: also accepts "real UI".
    - `e2e-unknown-driver-defaulted`: also accepts "auto. Its source is the bundled default".
    - `e2e-workspace-none-collide`: also accepts "port 5173 may already be taken".
    - `e2e-hub-driver-wins`: also accepts "playwright. It comes from the control skill's hub".
    - The three own-instance cases: also accept "is not reused" and "does not adopt it".
    - `e2e-worst-case-word-scenario`: also accepts the code-span "not the `worst-case` action".
    - `e2e-native-run-disabled`: also accepts "invocation refused (disableBundledSkills" when more reason text follows inside the parentheses.
  - Prompt fixes after the first smoke data, where both graders failed because of how the case was built:
    - `e2e-session-name-slug` keeps a blank line after the scenario. With the instructions appended on the same line, the run dropped "; rm -rf tmp" as an instruction.
    - `e2e-every-entry-point` states that each entry point drove and passed, because the run would not invent results.
