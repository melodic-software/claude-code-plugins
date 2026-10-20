import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterAll, describe, expect, it } from "vitest";

const preflight = path.join(import.meta.dirname, "preflight.mjs");
const sandboxes = [];
afterAll(() => {
  for (const dir of sandboxes) fs.rmSync(dir, { recursive: true, force: true });
});

function sandbox() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "preflight-"));
  sandboxes.push(root);
  return root;
}

function runPreflight(args, env = {}) {
  return spawnSync(process.execPath, [preflight, ...args], {
    encoding: "utf8",
    timeout: 60000,
    // An empty PATH hides every media tool, so the report must still print and exit 0.
    env: { ...process.env, CLAUDE_PLUGIN_DATA: "", PATH: "", ...env },
  });
}

describe("preflight.mjs", () => {
  it("reports every probe and exits 0 when nothing is installed", () => {
    const data = path.join(sandbox(), "knowledge-test");
    const result = runPreflight(["--data-dir", data]);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("video-extraction deps: MISSING");
    expect(result.stdout).toContain(`install target: ${path.join(data, "node_modules")}`);
    expect(result.stdout).toContain("yt-dlp: MISSING");
    expect(result.stdout).toContain("ffmpeg: MISSING");
    expect(result.stdout).toContain("ImageMagick: MISSING");
    expect(result.stdout).toContain("faster-whisper: not found");
    expect(fs.existsSync(data)).toBe(false);
  });

  it("reports the node dependencies installed when the package is in the data directory", () => {
    const data = path.join(sandbox(), "knowledge-test");
    fs.mkdirSync(path.join(data, "node_modules", "@melodic", "video-digestion"), { recursive: true });
    const result = runPreflight(["--data-dir", data]);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("video-extraction deps: installed");
  });

  it("reports an unknown data directory instead of failing", () => {
    const result = runPreflight([]);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("video-extraction deps: UNKNOWN");
  });

  it("reports an unsubstituted placeholder instead of failing", () => {
    const result = runPreflight(["--data-dir", "<plugin-data>"]);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("unsubstituted placeholder");
  });

  // A stub interpreter: an executable script that exits 0, so `-c "import faster_whisper"` passes.
  function stubPython(name) {
    const stub = path.join(sandbox(), name);
    fs.writeFileSync(stub, "#!/bin/sh\nexit 0\n", { mode: 0o755 });
    return stub;
  }

  it.skipIf(process.platform === "win32")(
    "ignores a literal ${user_config...} --asr-python and probes the option's env value",
    () => {
      const stub = stubPython("env-python");
      const result = runPreflight(["--asr-python", "${user_config.asr_python}"], {
        CLAUDE_PLUGIN_OPTION_ASR_PYTHON: stub,
      });
      expect(result.status).toBe(0);
      expect(result.stdout).toContain(`faster-whisper: available (via ${stub})`);
    },
  );

  it.skipIf(process.platform === "win32")(
    "prefers a real --asr-python over the option's env value",
    () => {
      const flag = stubPython("flag-python");
      const env = stubPython("env-python");
      const result = runPreflight(["--asr-python", flag], { CLAUDE_PLUGIN_OPTION_ASR_PYTHON: env });
      expect(result.status).toBe(0);
      expect(result.stdout).toContain(`faster-whisper: available (via ${flag})`);
    },
  );
});
