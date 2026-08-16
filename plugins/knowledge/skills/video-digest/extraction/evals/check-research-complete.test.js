import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { checkResearchComplete } from "./check-research-complete.js";

describe("checkResearchComplete agenda gate", () => {
  /** @type {string} */
  let sliceDir;

  beforeEach(() => {
    sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "check-research-"));
    fs.mkdirSync(path.join(sliceDir, "research"), { recursive: true });
    fs.writeFileSync(path.join(sliceDir, "RESEARCH.md"), "R".repeat(250));
    fs.writeFileSync(path.join(sliceDir, "research", "claim-inventory.md"), "# claims\n");
  });

  afterEach(() => {
    fs.rmSync(sliceDir, { recursive: true, force: true });
  });

  /** @param {string} body */
  function writeAgenda(body) {
    fs.writeFileSync(path.join(sliceDir, "research", "research-agenda.md"), body);
  }

  /** @param {number} count */
  function writeFindings(count) {
    const dir = path.join(sliceDir, "research", "findings");
    fs.mkdirSync(dir, { recursive: true });
    for (let i = 0; i < count; i++) {
      fs.writeFileSync(path.join(dir, `finding-${i}.md`), "# finding\n");
    }
  }

  it("fails when the agenda file is missing", () => {
    expect(checkResearchComplete(sliceDir)).toBe(1);
  });

  it("fails when an agenda row is still pending", () => {
    writeAgenda("| claim | T1 | pending |\n");
    expect(checkResearchComplete(sliceDir)).toBe(1);
  });

  it("passes with a resolved agenda backed by a finding", () => {
    writeAgenda("| claim | T1 | done |\n");
    writeFindings(1);
    expect(checkResearchComplete(sliceDir)).toBe(0);
  });
});
