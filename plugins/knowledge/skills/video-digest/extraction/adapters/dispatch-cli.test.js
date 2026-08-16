import { beforeEach, describe, expect, it, vi } from "vitest";

import { runTranscriptCli } from "../transcript/run-transcript.js";
import { runWatchCli } from "../watch/run-watch.js";

const captured = vi.hoisted(() => ({ stderr: /** @type {string[]} */ ([]) }));

vi.mock("@melodic/video-digestion/shared/terminal", () => ({
  writeStderr: (/** @type {unknown} */ text) => {
    captured.stderr.push(String(text));
  },
  writeStdout: () => {},
}));

describe("unknown-host dispatch through the CLI wrappers", () => {
  beforeEach(() => {
    captured.stderr.length = 0;
  });

  it("transcript CLI exits non-zero for an unowned host, listing supported sources", async () => {
    const code = await runTranscriptCli(["node", "run-transcript.js", "https://vimeo.com/1"]);
    expect(code).toBe(1);
    const stderr = captured.stderr.join("\n");
    expect(stderr).toContain("Unsupported source URL");
    expect(stderr).toContain("youtube.com");
    expect(stderr).toContain("youtu.be");
  });

  it("watch CLI exits non-zero for an unowned host, listing supported sources", async () => {
    const code = await runWatchCli(["node", "run-watch.js", "https://vimeo.com/1"]);
    expect(code).toBe(1);
    const stderr = captured.stderr.join("\n");
    expect(stderr).toContain("Unsupported source URL");
    expect(stderr).toContain("youtube.com");
  });

  it("transcript CLI exits non-zero when the owning adapter declines the URL", async () => {
    const code = await runTranscriptCli([
      "node",
      "run-transcript.js",
      "https://www.youtube.com/@somechannel",
    ]);
    expect(code).toBe(1);
    expect(captured.stderr.join("\n")).toContain("Unsupported source URL");
  });
});
