import { readFileSync } from "node:fs";

export const REGISTRY = JSON.parse(readFileSync(new URL("../../lane-registry.json", import.meta.url), "utf8"));

const LOCAL = "./.github/workflows/";

export function laneJob(workflow, id, registry = REGISTRY) {
  const job = registry.workflows[workflow]?.jobs?.[id];
  if (job === undefined) {
    throw new Error(`lane-registry.json names no job ${id} in ${workflow}`);
  }
  return { id, name: job.name, earlier: job.earlier ?? [], calls: job.calls, status: job.status ?? [] };
}

export function listedJob(workflow, id, inner, registry = REGISTRY) {
  const job = laneJob(workflow, id, registry);
  if (inner === undefined) {
    return { id, name: job.name, earlier: job.earlier };
  }
  if (!job.calls?.startsWith(LOCAL) || job.earlier.length > 0) {
    throw new Error(`${workflow} job ${id} is not a local workflow call with one name, so no listed name pairs its earlier names with the called job's`);
  }
  const called = laneJob(job.calls.slice(LOCAL.length), inner, registry);
  return { id: `${id} / ${inner}`, name: `${job.name} / ${called.name}`, earlier: [] };
}

export const jobNames = (workflow, id, registry = REGISTRY) => {
  const job = laneJob(workflow, id, registry);
  return [job.name, ...job.earlier];
};

export const callers = (workflow, called, registry = REGISTRY) =>
  Object.keys(registry.workflows[workflow]?.jobs ?? {}).filter((id) => registry.workflows[workflow].jobs[id].calls === called);

export function statusChecks(workflow, registry = REGISTRY) {
  const id = Object.keys(registry.workflows[workflow]?.jobs ?? {}).find((job) => registry.workflows[workflow].jobs[job].status !== undefined);
  if (id === undefined) {
    throw new Error(`lane-registry.json names no status job in ${workflow}`);
  }
  const names = jobNames(workflow, id, registry);
  return laneJob(workflow, id, registry).status.flatMap((status) => names.map((caller) => `${caller} / ${status}`));
}

export const reviewLanes = (registry = REGISTRY) =>
  Object.entries(registry.workflows).flatMap(([workflow, { footer }]) => (footer === undefined ? [] : [{ footer, workflow }]));
