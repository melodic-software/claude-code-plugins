// ci-workflows files at one commit, for tests that check this repository
// against the commit its workflows pin. Needs network: a fetch that fails or
// answers non-200 throws, so the calling test fails rather than skips.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

import { CLASSIFIER_FILES, loadLauncher } from "../plugin-eval/eval-handoff.mjs";

export async function fetchAtPin(pin, path) {
  const url = `https://raw.githubusercontent.com/melodic-software/ci-workflows/${pin}/${path}`;
  const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error(`${url} answered ${response.status}`);
  return response.text();
}

// run-claude-cli's lane.cjs exports at <pin>.
export async function laneAtPin(pin) {
  const root = mkdtempSync(join(tmpdir(), "ci-workflows-at-pin-"));
  try {
    for (const path of CLASSIFIER_FILES) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), await fetchAtPin(pin, path));
    }
    return loadLauncher(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
