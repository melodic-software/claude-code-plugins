#!/usr/bin/env node
// policy-probe.mjs: judges the eval policy probe's stream (`claude -p
// --output-format stream-json --verbose`) for the four calls the eval legs'
// probe step asks for. Each call is denied (the result's permission_denials
// records it), made and not denied (a tool_use with no matching denial: the
// policy let it through), or not made. A session can end normally without
// making every call, since no `claude` flag forces a tool call; that proves
// nothing about the policy either way, so it is reported as unproven, never as
// a policy failure.
//
// Env: PROBE (the stream's path), RUNNER_ROOT.
// Exit 0: all four denied. Exit 1: a call made and not denied, or a session
// that errored before making every call. Exit 3: a session that ended normally
// without making every call, which the caller runs again.
// Prints one line: the reason, then the probe's facts. The facts hold only
// counts and tokens checked against fixed patterns, never text from the
// stream, which can hold what a call returned.
import { readFileSync } from "node:fs";
import process from "node:process";
import { fileURLToPath } from "node:url";

export const expectedCalls = (runnerRoot) => [
  ["Read", "/proc/self/environ"],
  ["Read", `${runnerRoot}/.runner`],
  ["Grep", "/proc/self"],
  ["Glob", "/proc/self"],
];

const pathOf = (input) => String(input?.file_path ?? input?.path ?? "");
const token = (value, pattern) => (pattern.test(String(value)) ? String(value) : "other");

export function judgeProbe(text, runnerRoot) {
  const lines = text.split("\n").filter((line) => line !== "");
  const messages = lines.flatMap((line) => {
    try {
      const value = JSON.parse(line);
      return value && typeof value === "object" && !Array.isArray(value) ? [value] : [];
    } catch {
      return [];
    }
  });
  const result = messages.filter((m) => m.type === "result").at(-1) ?? null;
  const uses = messages
    .filter((m) => m.type === "assistant")
    .flatMap((m) => (Array.isArray(m.message?.content) ? m.message.content : []))
    .filter((block) => block && typeof block === "object" && block.type === "tool_use");
  const denials = Array.isArray(result?.permission_denials) ? result.permission_denials : [];

  const facts = [
    `result=${result ? "present" : "none"}`,
    `subtype=${token(result?.subtype ?? "none", /^[a-z_]{1,40}$/)}`,
    `terminal_reason=${token(result?.terminal_reason ?? "none", /^[a-z_]{1,40}$/)}`,
    `is_error=${token(result?.is_error ?? "none", /^(true|false|none)$/)}`,
    `api_error_status=${token(result?.api_error_status ?? "none", /^([0-9]{3}|none)$/)}`,
    `num_turns=${token(result?.num_turns ?? "none", /^([0-9]{1,4}|none)$/)}`,
    `tool_calls=${uses.length ? uses.map((u) => (["Read", "Grep", "Glob"].includes(u.name) ? u.name : "other")).join(",") : "none"}`,
    `denials=${denials.length}`,
    `unparsable_lines=${lines.length - messages.length}`,
  ].join(" ");

  const calls = expectedCalls(runnerRoot).map(([tool, prefix]) => ({
    tool,
    prefix,
    denied: denials.some((d) => d?.tool_name === tool && pathOf(d.tool_input).startsWith(prefix)),
    made: uses.some((u) => u.name === tool && pathOf(u.input).startsWith(prefix)),
  }));
  const say = (code, reason) => ({ code, line: `${reason} (probe: ${facts})` });

  if (calls.every((c) => c.denied)) return say(0, "the managed policy denied the probe's Read, Grep and Glob calls");
  const leaked = calls.find((c) => c.made && !c.denied);
  if (leaked) return say(1, `the managed policy did not record a denied ${leaked.tool} of ${leaked.prefix}`);
  const missing = calls.find((c) => !c.denied);
  if (result?.subtype !== "success") {
    return say(1, `the probe's session ended in error before its ${missing.tool} of ${missing.prefix}, so it proved nothing about the policy`);
  }
  if (uses.length === 0) return say(3, "the probe's session made no tool call, so it proved nothing about the policy");
  return say(3, `the probe's session never made its ${missing.tool} of ${missing.prefix}, so it proved nothing about the policy`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  let text = "";
  try {
    text = readFileSync(process.env.PROBE ?? "", "utf8");
  } catch {
    // An unreadable stream judges as an empty one: no result, so an error.
  }
  const { code, line } = judgeProbe(text, process.env.RUNNER_ROOT ?? "");
  process.stdout.write(`${line}\n`);
  process.exitCode = code;
}
