import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { snapshotBootstrapContactSheets } from "./snapshot-bootstrap.js";

describe("snapshotBootstrapContactSheets", () => {
  let sliceDir;
  let sheetsDir;

  beforeEach(() => {
    sliceDir = mkdtempSync(join(tmpdir(), "slice-"));
    sheetsDir = mkdtempSync(join(tmpdir(), "youtube-sheets-"));
    writeFileSync(join(sheetsDir, "sheet_001.jpg"), "fake-jpg-bytes");
  });

  afterEach(() => {
    rmSync(sliceDir, { recursive: true, force: true });
    rmSync(sheetsDir, { recursive: true, force: true });
  });

  it("tokenizes snapshot-meta.json sourceDir — no machine-local temp path leaks", () => {
    mkdirSync(join(sliceDir, "run-state"), { recursive: true });
    writeFileSync(
      join(sliceDir, "run-state", "watch.json"),
      `${JSON.stringify({ tempSession: { contactSheetsDir: sheetsDir } }, null, 2)}\n`,
      "utf8",
    );

    const result = snapshotBootstrapContactSheets(sliceDir);
    expect(result.copied).toBe(1);

    const meta = JSON.parse(
      readFileSync(join(sliceDir, "key-frames", "contact-sheets", "snapshot-meta.json"), "utf8"),
    );
    expect(meta.sourceDir).toMatch(/^\{tmp\}\//);
    expect(meta.sourceDir).not.toMatch(/AppData|[/\\]Temp[/\\]/);
  });

  it("writes a local .gitignore excluding the snapshot JPG binaries", () => {
    mkdirSync(join(sliceDir, "run-state"), { recursive: true });
    writeFileSync(
      join(sliceDir, "run-state", "watch.json"),
      `${JSON.stringify({ tempSession: { contactSheetsDir: sheetsDir } }, null, 2)}\n`,
      "utf8",
    );

    snapshotBootstrapContactSheets(sliceDir);

    const ignore = readFileSync(
      join(sliceDir, "key-frames", "contact-sheets", ".gitignore"),
      "utf8",
    );
    expect(ignore).toContain("*.jpg");
  });
});
