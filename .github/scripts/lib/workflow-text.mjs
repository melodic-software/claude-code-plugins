// Reads jobs, steps and their inputs out of a workflow's text, for the
// credential-chain truth tables. Single-line values and folded (`>-`) job
// conditions only: the shapes the lane workflows use.
import assert from "node:assert/strict";

export function workflowText(text) {
  const job = (id) => {
    const match = new RegExp(`^ {2}${id}:\\n[\\s\\S]*?(?=^ {2}\\S|(?![\\s\\S]))`, "m").exec(text);
    assert.ok(match, `job ${id}`);
    return match[0];
  };
  const jobIf = (id) => {
    const body = job(id);
    const folded = /^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(body);
    if (folded) return folded[1].replace(/\s+/g, " ").trim();
    const line = /^ {4}if: (.*)$/m.exec(body);
    return line ? line[1] : "true";
  };
  const outputs = (id) => {
    const block = /^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(job(id));
    const map = {};
    for (const [, name, value] of (block?.[1] ?? "").matchAll(/^ {6}([\w-]+): (.*)$/gm)) map[name] = value;
    return map;
  };
  const step = (jobId, stepId) => {
    const steps = job(jobId).split(/\n(?= {6}- name: )/).slice(1);
    const found = steps.filter((s) => new RegExp(`^ {8}id: ${stepId}$`, "m").test(s));
    assert.equal(found.length, 1, `${jobId} step ${stepId}`);
    const body = found[0];
    const inputs = {};
    const withBlock = /^ {8}with:\n((?: {10}.*\n?)+)/m.exec(body);
    for (const [, name, value] of (withBlock?.[1] ?? "").matchAll(/^ {10}([\w-]+): (.*)$/gm)) inputs[name] = value;
    return { text: body, if: /^ {8}if: (.*)$/m.exec(body)?.[1] ?? "", inputs };
  };
  return { job, jobIf, outputs, step };
}
