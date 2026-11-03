// Exits 1, naming the grader and file, when a detection grader of an st-* case matches the text of
// a file in that case's seeded workspace. Each file is tested as a stand-in for a report that
// quotes it back. A must-not-flag grader (match: not_contains) is skipped: a match there fails the
// run, so quoting cannot raise a score.
//
//   st-grader-echo.mjs <case dir> <workspace dir>
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";

const [caseDir, workspace] = process.argv.slice(2);

function field(frontmatter, key) {
  const line = frontmatter.split("\n").find((l) => l.startsWith(`${key}:`));
  if (!line) {
    return undefined;
  }
  const value = line.slice(key.length + 1).trim();
  return value.startsWith("'") ? value.slice(1, -1).replaceAll("''", "'") : value;
}

function files(dir) {
  return readdirSync(dir).flatMap((entry) => {
    if (entry === ".git") {
      return [];
    }
    const path = join(dir, entry);
    return statSync(path).isDirectory() ? files(path) : [path];
  });
}

const graderDir = join(caseDir, "graders");
const texts = files(workspace).map((path) => [path, readFileSync(path, "utf8")]);
const hits = [];
for (const entry of readdirSync(graderDir)) {
  const frontmatter = readFileSync(join(graderDir, entry), "utf8").split(/^---$/m)[1] ?? "";
  const pattern = field(frontmatter, "pattern");
  if (field(frontmatter, "match") === "not_contains" || !pattern) {
    continue;
  }
  const regex = new RegExp(pattern, field(frontmatter, "flags") ?? "");
  for (const [path, text] of texts) {
    if (regex.test(text)) {
      hits.push(`${entry} matches ${path.slice(workspace.length + 1)}`);
    }
  }
}
if (hits.length > 0) {
  console.error(hits.join("; "));
  process.exit(1);
}
