#!/usr/bin/env node
// Unit tests for the unassigned-CLI rule in transcript.mjs: a trial assigned one browser CLI is
// voided when a Bash call runs the other one, however the shell spells the call, and is not voided
// when the other CLI's name only appears as text (an echo, a grep pattern, a quoted argument, a
// comment).

import { commandWords, parseTranscript } from "./transcript.mjs";

let PASS = 0;
let FAIL = 0;
const check = (name, cond, detail) => {
  if (cond) {
    console.log(`ok: ${name}`);
    PASS += 1;
  } else {
    console.error(`FAIL: ${name}${detail ? ` - ${detail}` : ""}`);
    FAIL += 1;
  }
};

const bash = (cmd) => JSON.stringify({ message: { role: "assistant", content: [{ type: "tool_use", id: "t1", name: "Bash", input: { command: cmd } }] } });
const voids = (tool, cmd) => parseTranscript(bash(cmd), { tool }).contamination.some((c) => c.startsWith("invoked the unassigned"));

// [assigned tool, Bash command, voids the trial]
const CASES = [
  // The trial's own CLI, alone or chained.
  ["playwright-cli", "playwright-cli -s=x open http://127.0.0.1:4400", false],
  ["playwright-cli", "playwright-cli -s=x snapshot && playwright-cli -s=x click e3", false],
  ["agent-browser", "cd /tmp && agent-browser snapshot -i", false],
  ["agent-browser", "agent-browser --session x open http://127.0.0.1:4400/T01", false],
  // The other CLI, however it is reached.
  ["playwright-cli", "agent-browser open x", true],
  ["agent-browser", "echo hi | playwright-cli snapshot", true],
  ["agent-browser", "npx playwright-cli --help", true],
  ["playwright-cli", "AGENT_BROWSER_SESSION=x agent-browser open url", true],
  ["agent-browser", "FOO=1 BAR=2 playwright-cli open", true],
  ["playwright-cli", "which agent-browser", true],
  ["playwright-cli", "command agent-browser foo", true],
  ["playwright-cli", "env agent-browser foo", true],
  ["playwright-cli", "exec agent-browser foo", true],
  ["playwright-cli", "sudo -E agent-browser open x", true],
  ["playwright-cli", "time agent-browser snapshot", true],
  ["playwright-cli", "(agent-browser foo)", true],
  ["playwright-cli", "/usr/local/bin/agent-browser foo", true],
  ["playwright-cli", "out=$(agent-browser get title)", true],
  ["playwright-cli", 'title="$(agent-browser get title)"', true],
  ["playwright-cli", '"agent-browser" status', true],
  ["playwright-cli", "'agent-browser' status", true],
  ["playwright-cli", "playwright-cli click '#x'; agent-browser status", true],
  ["playwright-cli", 'playwright-cli click "#submit" && agent-browser snapshot', true],
  ["playwright-cli", "playwright-cli snapshot # note\nagent-browser open x", true],
  // The other CLI's name as text only.
  ["playwright-cli", "echo agent-browser-like", false],
  ["playwright-cli", "grep -v agent-browser /usr/local/bin/* 2>/dev/null", false],
  ["playwright-cli", 'echo "falling back, not using agent-browser here"', false],
  ["playwright-cli", "echo 'agent-browser is not used'", false],
  ["playwright-cli", 'echo "agent-browser"', false],
  ["playwright-cli", 'grep -v "agent-browser" log.txt', false],
  ["playwright-cli", 'playwright-cli fill e3 "not agent-browser; really"', false],
  ["playwright-cli", "playwright-cli fill e1 'x;agent-browser'", false],
  ["playwright-cli", "playwright-cli click '#x'", false],
  ["playwright-cli", "playwright-cli snapshot # not agent-browser", false],
  ["playwright-cli", "playwright-cli snapshot # then agent-browser", false],
  ["playwright-cli", "ls node_modules | grep agent", false],
  ["agent-browser", "cat out.txt | grep playwright-cli", false],
];

for (const [tool, cmd, want] of CASES) {
  const got = voids(tool, cmd);
  check(`${tool} | ${JSON.stringify(cmd)} ${want ? "voids" : "stays clean"}`, got === want, `got ${got}, words ${JSON.stringify(commandWords(cmd))}`);
}

// No assigned tool (an older caller) never voids on the CLI rule.
check("no assigned tool never voids", !parseTranscript(bash("agent-browser open x")).contamination.some((c) => c.startsWith("invoked the unassigned")));

console.log(`\n${PASS} passed, ${FAIL} failed`);
process.exit(FAIL ? 1 : 0);
