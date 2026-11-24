import assert from "node:assert/strict";

const fields = (block, indent) => {
  const map = {};
  for (const [, name, value] of (block ?? "").matchAll(new RegExp(`^ {${indent}}([\\w-]+): (.*)$`, "gm"))) map[name] = value;
  return map;
};

export const ifOf = (block, indent) => {
  const match = new RegExp(`^ {${indent}}if: (?:>-\\n((?: {${indent + 2}}.*(?:\\n|$))+)|(.*)$)`, "m").exec(block);
  return match?.[1]?.replace(/\s+/g, " ").trim() ?? match?.[2] ?? "";
};

export const stepsOf = (jobBlock) =>
  jobBlock
    .split(/\n(?= {6}- name: )/)
    .slice(1)
    .map((text) => ({ name: /^ {6}- name: (.*)$/m.exec(text)[1], text: text.replace(/\s*(?:\n {6}#.*)*\s*$/, "\n") }));

const stepFields = ({ name, text }) => ({
  name,
  text,
  if: ifOf(text, 8),
  inputs: fields(/^ {8}with:\n((?: {10}.*\n?)+)/m.exec(text)?.[1], 10),
  env: fields(/^ {8}env:\n((?: {10}.*\n?)+)/m.exec(text)?.[1], 10),
});

export function workflowText(text) {
  const jobs = text.slice(Math.max(0, text.indexOf("\njobs:\n")));
  const ids = [...jobs.matchAll(/^ {2}([\w-]+):$/gm)].map((match) => match[1]);
  const job = (id) => {
    const match = new RegExp(`^ {2}${id}:\\n[\\s\\S]*?(?=^ {2}\\S|(?![\\s\\S]))`, "m").exec(jobs);
    assert.ok(match, `job ${id}`);
    return match[0];
  };
  const jobIf = (id) => ifOf(job(id), 4) || "true";
  const outputs = (id) => fields(/^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(job(id))?.[1], 6);
  const steps = (jobId) => stepsOf(job(jobId));
  const only = (found, what) => {
    assert.equal(found.length, 1, what);
    return stepFields(found[0]);
  };
  const step = (jobId, stepId) => only(steps(jobId).filter((s) => new RegExp(`^ {8}id: ${stepId}$`, "m").test(s.text)), `${jobId} step ${stepId}`);
  const stepNamed = (jobId, name) => only(steps(jobId).filter((s) => s.name === name), `${jobId} step ${name}`);
  return { ids, job, jobIf, outputs, steps, step, stepNamed };
}
