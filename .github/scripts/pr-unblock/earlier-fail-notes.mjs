// The notes of pr-verify's FAILs at the heads behind the merge gate's
// verify:earlier-fail refusal, read from their verdict artifacts, the notes'
// source of truth, for an address-feedback round whose fail-note threads are
// all resolved (address-feedback.mjs select, #12809). Run by the select job
// with its GITHUB_TOKEN (actions, contents and pull-requests read).
//
// For each FAILed head: the FAIL's index artifact for that head
// (write-verdict.mjs failIndexNames, an exact-name lookup) names the pr-verify
// runs that FAILed it; each such run's artifacts hold the verdict, named for
// this pull request and head (write-verdict.mjs NAME). A run counts only when
// the merge gate's reader would count it (resolve-pr.mjs countedBy: a
// pr-verify.yml run on the default branch of this repository), so no other
// workflow's artifact hands the model its notes; another run is passed over.
// The verdict is read with
// verify-notes.mjs readVerdict and rendered with noteComments, the text
// pr-verify's notes would have posted, quoted as data. Every other read that
// fails, a listing that does not hold its count, a head with no counted FAIL
// left to read, a withheld FAIL and more than MAX_NOTE_ITEMS items throw: the
// caller fails closed.
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { countedBy } from "../pr-verify/resolve-pr.mjs";
import { INDEX_PREFIX, isVerdictName, NAME } from "../pr-verify/write-verdict.mjs";
import { noteComments, readVerdict } from "./verify-notes.mjs";

// The most work items one round takes (judgment: three FAILed heads at the
// cap, each with a summary and a handful of files).
export const MAX_NOTE_ITEMS = 50;

// The note ids, thread-scope.mjs NOTE_ID.
export const noteId = (i) => `VNOTE_${i + 1}`;

const live = (artifact) => artifact?.expired !== true;

// Whether `name` is this pull request's FAIL verdict at `head`.
function failFor(name, pr, head) {
  const match = isVerdictName(name) ? NAME.exec(name) : null;
  return match !== null && match[1] === String(pr) && match[2] === head && match[3] === "fail";
}

// One page of an artifact listing that must hold its own count.
async function listing(actions, path) {
  const page = await actions.read(`${path}${path.includes("?") ? "&" : "?"}per_page=100`);
  const artifacts = page?.artifacts;
  if (!Array.isArray(artifacts) || page.total_count !== artifacts.length) {
    throw new Error(`${path} does not list its ${page?.total_count} artifacts on one page`);
  }
  return artifacts;
}

// verdict.json from an artifact's zip, as the upload holds it at its root.
export function unzipVerdict(zip, { dir = process.env.RUNNER_TEMP || tmpdir() } = {}) {
  const work = mkdtempSync(join(dir, "earlier-fail-"));
  try {
    const file = join(work, "verdict.zip");
    writeFileSync(file, zip);
    return execFileSync("unzip", ["-p", file, "verdict.json"], { encoding: "utf8", maxBuffer: 4 << 20 });
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

// `actions`: { read(path) -> JSON, download(artifactId) -> Buffer }, paths
// under the API root. Returns [{ id, head, path, body }], in the heads' order.
export async function earlierFailNotes({ actions, repository, pr, heads, files, base = "main", unzip = unzipVerdict }) {
  const repo = `/repos/${repository}`;
  // countedBy's client: reads only.
  const github = (method, path) => (method === "GET" ? actions.read(path) : Promise.reject(new Error(`${method} is not a read`)));
  const items = [];
  for (const head of heads) {
    const index = await listing(actions, `${repo}/actions/artifacts?name=${encodeURIComponent(`${INDEX_PREFIX}sha-${head}`)}`);
    const runs = [...new Set(index.filter(live).map((artifact) => artifact.workflow_run?.id))];
    let read = 0;
    for (const runId of runs) {
      if (!Number.isSafeInteger(runId) || runId < 1) {
        throw new Error(`a FAIL index of ${head} names no run`);
      }
      const fails = (await listing(actions, `${repo}/actions/runs/${runId}/artifacts`)).filter((artifact) => live(artifact) && failFor(artifact.name, pr, head));
      if (fails.length === 0) {
        continue;
      }
      // A run the gate would not count (another workflow's, or one whose
      // read fails) is passed over, as the gate's reader passes it over.
      if (!(await countedBy({ github, repository, runId, verdict: "fail", base }))) {
        continue;
      }
      for (const artifact of fails) {
        const verdict = readVerdict(artifact.name, unzip(await actions.download(artifact.id)));
        if (verdict.verdict !== "fail" || verdict.pr !== pr || verdict.head !== head || verdict.withheld) {
          throw new Error(`${artifact.name} is not a readable FAIL of #${pr} at ${head}`);
        }
        items.push(...noteComments({ head, summary: verdict.summary, notes: verdict.notes, files }).map(({ path, body }) => ({ head, path, body })));
        read += 1;
      }
    }
    if (read === 0) {
      throw new Error(`no FAIL verdict artifact of #${pr} at ${head} is left to read`);
    }
  }
  if (items.length === 0 || items.length > MAX_NOTE_ITEMS) {
    throw new Error(`the FAILs hold ${items.length} note item(s), not 1 to ${MAX_NOTE_ITEMS}`);
  }
  return items.map((item, i) => ({ id: noteId(i), ...item }));
}
