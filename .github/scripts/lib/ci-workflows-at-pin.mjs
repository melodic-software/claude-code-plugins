import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

import { CLASSIFIER_FILES, loadLauncher } from "../plugin-eval/eval-handoff.mjs";

const fetched = new Map();

export function fetchAtPin(pin, path) {
  const url = `https://raw.githubusercontent.com/melodic-software/ci-workflows/${pin}/${path}`;
  if (!fetched.has(url)) {
    fetched.set(
      url,
      fetch(url, { signal: AbortSignal.timeout(15000) }).then((response) => {
        if (!response.ok) throw new Error(`${url} answered ${response.status}`);
        return response.text();
      }),
    );
  }
  return fetched.get(url);
}

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
