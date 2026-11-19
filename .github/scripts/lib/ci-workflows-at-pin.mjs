import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

import { CONTRACT_FILES, contractFiles, loadContract } from "../plugin-eval/eval-handoff.mjs";

const fetched = new Map();
const ATTEMPTS = 3;

async function fetchText(url) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
      if (response.ok) return await response.text();
      if (response.status < 500 || attempt === ATTEMPTS) throw new Error(`${url} answered ${response.status}`, { cause: "final" });
    } catch (error) {
      if (error.cause === "final" || attempt === ATTEMPTS) throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, 2000 * attempt));
  }
}

export function fetchAtPin(pin, path) {
  const url = `https://raw.githubusercontent.com/melodic-software/ci-workflows/${pin}/${path}`;
  if (!fetched.has(url)) fetched.set(url, fetchText(url));
  return fetched.get(url);
}

export async function contractFilesAtPin(pin) {
  return contractFiles(await fetchAtPin(pin, CONTRACT_FILES));
}

export async function contractAtPin(pin) {
  const root = mkdtempSync(join(tmpdir(), "ci-workflows-at-pin-"));
  try {
    for (const path of [CONTRACT_FILES, ...(await contractFilesAtPin(pin))]) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), await fetchAtPin(pin, path));
    }
    return loadContract(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
