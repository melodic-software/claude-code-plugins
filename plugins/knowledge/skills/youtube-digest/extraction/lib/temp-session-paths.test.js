import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  normalizePortableTempPath,
  resolveTempPath,
  resolveTempSession,
  serializeTempPath,
  serializeTempSession,
} from "./temp-session-paths.js";

describe("temp-session-paths", () => {
  it("round-trips paths under os tmpdir", () => {
    const abs = path.join(os.tmpdir(), "youtube-frames-abc");
    const serialized = serializeTempPath(abs);
    expect(serialized).toBe("{tmp}/youtube-frames-abc");
    expect(resolveTempPath(serialized)).toBe(abs);
  });

  it("serializes temp session block", () => {
    const abs = path.join(os.tmpdir(), "youtube-sheets-x");
    const out = serializeTempSession({ contactSheetsDir: abs, acquiredAt: "t" });
    expect(out.contactSheetsDir).toBe("{tmp}/youtube-sheets-x");
    expect(resolveTempSession(out).contactSheetsDir).toBe(abs);
  });

  it("strips accidental prefix before embedded {tmp}", () => {
    const broken = `/repos/foo/{tmp}/youtube-frames-neUPQR`;
    expect(normalizePortableTempPath(broken)).toBe("{tmp}/youtube-frames-neUPQR");
  });
});
