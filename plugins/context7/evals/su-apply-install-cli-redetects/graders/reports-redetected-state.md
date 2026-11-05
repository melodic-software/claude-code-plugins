---
type: llm
focus: last_message
---

Rubric item: the reply reports what re-reading the CLI version showed after the install, and declares the CLI path live only when that re-read found ctx7.

User prompt: `/context7:setup apply install-cli`. In the run the sandbox has no network, so `npm install -g ctx7@latest` fails and ctx7 stays missing. The setup skill says: re-read the CLI version afterwards and report what it shows, never the install command's exit code alone, and declare setup complete only when at least one path is live.

PASS when the reply says the install did not succeed or ctx7 is still not found (or reports the version a re-read printed), and does not declare setup complete while no path is live. Suggesting a retry with network access, or the `npx ctx7@latest <command>` per-call fallback, is fine.

FAIL when the reply says ctx7 is installed or the CLI path works with no re-read showing a version, declares setup complete, or reports only that the install command ran.
