import { appendFileSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const SANDBOX_REFUSAL = /^bwrap: /m;

const resultText = (content) =>
  typeof content === "string" ? content : (content ?? []).map((part) => part?.text ?? "").join("\n");

export function sandboxRefusals(messages) {
  return messages
    .flatMap((message) => (message?.type === "user" ? message.message?.content ?? [] : []))
    .filter((part) => part?.type === "tool_result" && part.is_error === true && SANDBOX_REFUSAL.test(resultText(part.content))).length;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const { EXECUTION_FILE, GITHUB_JOB, GITHUB_STEP_SUMMARY } = process.env;
  const refusals = sandboxRefusals(JSON.parse(readFileSync(EXECUTION_FILE, "utf8")));
  if (refusals > 0) {
    const line = `the sandbox refused to start ${refusals} tool call(s) (a bwrap error); the sealed transcript has the text`;
    console.log(`::error::${line}`);
    if (GITHUB_STEP_SUMMARY) appendFileSync(GITHUB_STEP_SUMMARY, `### maintenance-scan-architecture / ${GITHUB_JOB}\n\nFailed: ${line}.\n`);
    process.exitCode = 1;
  }
}
