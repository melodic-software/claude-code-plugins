import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { gzipSync } from "node:zlib";

import { parsePublicKey, sealRecord } from "../../.github/actions/seal-lane-output/seal.mjs";
import { tempDir } from "../../lib/test-tmp.mjs";
import { ENTRY, main, PAYLOAD } from "./pull.mjs";
import { paths } from "./store.mjs";

export const MARKER = "plaintext-marker-5d21";
export const NOW = Date.parse("2026-11-02T12:00:00Z");
export const REPO_ID = 1277265216;
export const MESSAGES = [
  { type: "system", subtype: "init", model: "claude-opus-5-5", session_id: "s" },
  { type: "assistant", message: { content: [{ type: "text", text: MARKER }] } },
  { type: "result", subtype: "success", is_error: false, num_turns: 7, duration_ms: 1200, usage: { input_tokens: 10, output_tokens: 20 }, modelUsage: { "claude-opus-5-5": {}, "claude-sonnet-5-5": {} } },
];
export const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, "Z");

export const zipOf = (entries) => Buffer.from(JSON.stringify(Object.fromEntries(Object.entries(entries).map(([k, v]) => [k, Buffer.from(v).toString("base64")]))));

export function artifact(id, { jobId = "check-intent", attempt = 1, runId = 42, createdAt = NOW - 60_000, fork = false, entries, record }) {
  return { id, name: `lane-transcript-${jobId}-${attempt}`, size_in_bytes: 100, expired: false, created_at: iso(createdAt), workflow_run: { id: runId, repository_id: REPO_ID, head_repository_id: fork ? 1 : REPO_ID }, zip: zipOf(entries ?? { [ENTRY]: record }) };
}

export function sealed(publicLine, { runId = 42, jobId = "check-intent", messages = MESSAGES } = {}) {
  return sealRecord(parsePublicKey(publicLine), PAYLOAD, gzipSync(Buffer.from(JSON.stringify(messages))), String(runId), jobId);
}

export function fakeDeps(artifacts, { now = NOW, runs = {}, failures = {}, workflowRuns = {} } = {}) {
  const calls = [];
  const sleeps = [];
  const byId = new Map(artifacts.map((a) => [a.id, a]));
  const left = { ...failures };
  return {
    calls,
    sleeps,
    now: () => now,
    sleep: (ms) => sleeps.push(ms),
    gh(args) {
      calls.push(args.join(" "));
      const url = args[1];
      const failing = Object.keys(left).find((suffix) => url.endsWith(suffix));
      if (failing && left[failing]-- > 0) throw Object.assign(new Error(`HTTP 502 ${MARKER}`), { status: 1 });
      let m = /actions\/artifacts\?name=([^&]+)&per_page=100&page=(\d+)$/.exec(url);
      if (m) {
        const page = artifacts.filter((a) => a.name === m[1]).slice((Number(m[2]) - 1) * 100, Number(m[2]) * 100);
        return Buffer.from(JSON.stringify({ artifacts: page.map(({ zip, ...a }) => a) }));
      }
      m = /actions\/workflows\/([^/]+)\/runs\?per_page=100$/.exec(url);
      if (m) return Buffer.from(JSON.stringify({ workflow_runs: workflowRuns[m[1]] ?? [] }));
      m = /actions\/artifacts\/(\d+)\/zip$/.exec(url);
      if (m) return byId.get(Number(m[1])).zip;
      m = /actions\/runs\/(\d+)$/.exec(url);
      if (m) return Buffer.from(JSON.stringify(runs[m[1]] ?? { path: ".github/workflows/pr-verify.yml", name: "pr-verify", event: "pull_request", head_branch: "feat/x", conclusion: "success" }));
      throw Object.assign(new Error("unexpected gh call"), { status: 9 });
    },
    unzip(args) {
      const entries = JSON.parse(readFileSync(args[1], "utf8"));
      if (args[0] === "-Z1") return Buffer.from(Object.keys(entries).join("\n"));
      return Buffer.from(entries[args[2]], "base64");
    },
  };
}

export function run(argv, { env = {}, deps } = {}) {
  let out = "";
  let err = "";
  const code = main(argv, env, deps, { out: (s) => (out += s), err: (s) => (err += s) });
  return { code, out, err };
}

export const sinkDir = () => path.join(tempDir("lane-transcripts-"), "sink");
export const FOREVER = Number.MAX_SAFE_INTEGER;
export const stateOf = (sink) => JSON.parse(readFileSync(paths(sink).state, "utf8"));
export const seedState = (sink, state) => {
  mkdirSync(sink, { recursive: true });
  writeFileSync(paths(sink).state, JSON.stringify(state));
};

export const listings = (deps) => deps.calls.filter((c) => c.includes("actions/artifacts?"));

export const WORKFLOWS = path.join(import.meta.dirname, "..", "..", ".github", "workflows");
export const workflowLines = () => readdirSync(WORKFLOWS).filter((f) => f.endsWith(".yml")).map((file) => [file, readFileSync(path.join(WORKFLOWS, file), "utf8").split("\n")]);
