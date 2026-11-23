import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const HERE = import.meta.dirname;

const DATA_FILES = [
  ["CONTEXT_FILE", "context.json"],
  ["PR_FILE", "pr.json"],
  ["SPEC_TEXT_FILE", "spec-text.json"],
  ["SPEC_FILE", "spec.json"],
  ["JOBS_FILE", "upstream-jobs.json"],
];

const fill = (template, pairs) => pairs.reduce((text, [token, value]) => text.replaceAll(token, () => value), template.replace(/\n+$/, ""));
const bullets = (paths) => paths.map((file) => `  - \`${file}\``).join("\n");

export function renderChunkNote({ template, manifestParts, dataDir, index, count }) {
  return fill(template, [
    ["MANIFEST_PARTS", bullets(manifestParts)],
    ["DATA_DIR", dataDir],
    ["CHUNK_INDEX", String(index)],
    ["CHUNK_COUNT", String(count)],
  ]);
}

export function renderPrompt({ template, parts, dataDir, note }) {
  const pairs = [["DIFF_PARTS", bullets(parts)], ...DATA_FILES.map(([token, file]) => [token, `${dataDir}/${file}`]), ["CHUNK_NOTE", note === undefined ? "" : `\n${note}`]];
  return `${fill(template, pairs)}\n`;
}

const listed = (dir, pattern) => {
  const names = readdirSync(dir).filter((name) => pattern.test(name)).sort();
  if (names.length === 0) throw new Error(`${dir} holds no ${pattern} file`);
  return names.map((name) => `${dir}/${name}`);
};

export function writePrompts({ dataDir, chunks, stem, templateDir = HERE }) {
  const template = readFileSync(path.join(templateDir, "prompt.md"), "utf8");
  const noteTemplate = chunks > 1 ? readFileSync(path.join(templateDir, "chunk-note.md"), "utf8") : undefined;
  const manifestParts = chunks > 1 ? listed(`${dataDir}/manifest`, /^part-.*\.txt$/) : [];
  for (let index = 1; index <= chunks; index += 1) {
    const note = noteTemplate && renderChunkNote({ template: noteTemplate, manifestParts, dataDir, index, count: chunks });
    const parts = listed(`${dataDir}/diff/chunk-${index}`, /^part-.*\.patch$/);
    writeFileSync(`${stem}-${index}.md`, renderPrompt({ template, parts, dataDir, note }));
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const { DATA, CHUNKS, PROMPT_STEM } = process.env;
    if (!DATA || !PROMPT_STEM || !/^[1-9][0-9]?$/.test(CHUNKS ?? "")) throw new Error("DATA, PROMPT_STEM and a chunk count of 1 to 99 are required");
    writePrompts({ dataDir: DATA, chunks: Number(CHUNKS), stem: PROMPT_STEM });
  } catch (error) {
    console.log(`::error::pr-verify could not write the prompts: ${error.message}`);
    process.exitCode = 1;
  }
}
