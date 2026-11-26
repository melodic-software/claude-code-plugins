import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const read = (name) => readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8");
const { commits: [template], files: sampleFiles, ...header } = JSON.parse(read("compare-sample.json"));
const sections = read("compare-sample.diff").split(/^(?=diff --git )/m);
const extra = sections.pop();
const modified = sampleFiles.findIndex((entry) => entry.status === "modified");

export const modifiedAs = (paths) => paths.map((path) => sections[modified].replaceAll(sampleFiles[modified].filename, path)).join("");
const COPIES = 300 / sampleFiles.length;

const files = [];
const diff = [];
for (let copy = 0; copy < COPIES; copy += 1) {
  sampleFiles.forEach((entry, at) => {
    const keys = ["filename", "previous_filename"].filter((key) => key in entry);
    const copied = Object.fromEntries(keys.map((key) => [key, copy === 0 ? entry[key] : `n${copy}/${entry[key]}`]));
    files.push({ ...entry, ...copied });
    diff.push(keys.reduce((text, key) => text.replaceAll(entry[key], copied[key]), sections[at]));
  });
}

export function chain(count, parent = header.merge_base_commit.sha) {
  const commits = [];
  for (let n = 1; n <= count; n += 1) {
    const sha = n.toString(16).padStart(40, "0");
    commits.push({ ...template, sha, parents: [{ sha: parent }] });
    parent = sha;
  }
  return commits;
}

const commits = chain(150);

export const LISTED = { ...header, ahead_by: 150, total_commits: 150, commits: commits.slice(0, 100), files };
export const PAGE_TWO = { ...header, ahead_by: 150, total_commits: 150, commits: commits.slice(100) };
export const DIFF_TEXT = [...diff, extra].join("");

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const dir = process.argv[2];
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "compare-paged-1.json"), JSON.stringify(LISTED));
  writeFileSync(join(dir, "compare-paged-2.json"), JSON.stringify(PAGE_TWO));
  writeFileSync(join(dir, "compare.diff"), DIFF_TEXT);
}
