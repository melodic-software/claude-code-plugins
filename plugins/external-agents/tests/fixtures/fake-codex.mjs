import { appendFileSync, readFileSync, writeFileSync } from "node:fs";

const scenario = JSON.parse(readFileSync(process.env.FAKE_SCENARIO, "utf8"));
const argv = process.argv.slice(2);
if (argv[0] === "app-server") {
  const spec = scenario.app_server ?? {};
  if (spec.exit !== undefined && !spec.messages) {
    appendFileSync(scenario.record, `${JSON.stringify({ argv, stdin: null })}\n`);
    process.exit(spec.exit);
  }
  const received = [];
  let buf = "";
  let replied = false;
  let hangTimer = null;
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => {
    buf += chunk;
    const lines = buf.split(/\r?\n/);
    buf = lines.pop() ?? "";
    for (const line of lines) {
      if (!line.trim()) continue;
      received.push(line);
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (msg.id === 1 && !replied) {
        replied = true;
        appendFileSync(scenario.record, `${JSON.stringify({ argv, stdin_lines: received })}\n`);
        if (spec.hang_ms) {
          hangTimer = setTimeout(() => process.exit(spec.exit ?? 0), spec.hang_ms);
        } else {
          for (const out of spec.messages ?? []) {
            process.stdout.write(`${typeof out === "string" ? out : JSON.stringify(out)}\n`);
          }
          if (spec.exit !== undefined) process.exit(spec.exit);
        }
      }
    }
  });
  process.stdin.on("end", () => {
    if (!replied) appendFileSync(scenario.record, `${JSON.stringify({ argv, stdin_lines: received, eof_before_reply: true })}\n`);
    if (hangTimer) clearTimeout(hangTimer);
    process.exit(spec.exit ?? 0);
  });
} else {
  const stdin = argv.at(-1) === "-" ? readFileSync(0, "utf8") : null;
  appendFileSync(scenario.record, `${JSON.stringify({ argv, stdin })}\n`);

  const answer = scenario.answers?.[argv.join(" ")];
  if (answer) {
    process.stdout.write(answer.stdout ?? "");
    process.stderr.write(answer.stderr ?? "");
    process.exit(answer.exit ?? 0);
  }
  if (argv[0] === "login") process.exit(scenario.login_exit ?? 0);
  if (argv[0] === "--version") {
    process.stdout.write(scenario.version ?? "codex-cli 0.0.1\n");
    process.exit(0);
  }
  if (argv.at(-1) === "--help") {
    const asked = argv.join(" ");
    if (scenario.help_empty?.includes(asked)) process.exit(0);
    const file = scenario.help?.[asked];
    if (file) (scenario.help_stderr?.includes(asked) ? process.stderr : process.stdout).write(readFileSync(file, "utf8"));
    process.exit(file ? 0 : 2);
  }
  if (scenario.stdout_file) process.stdout.write(readFileSync(scenario.stdout_file, "utf8"));
  if (scenario.stdout) process.stdout.write(scenario.stdout);
  if (scenario.stderr) process.stderr.write(scenario.stderr);
  const out = argv.indexOf("-o");
  if (out !== -1 && scenario.final !== undefined) writeFileSync(argv[out + 1], scenario.final);
  setTimeout(() => process.exit(scenario.exit ?? 0), scenario.sleep_ms ?? 0);
}
