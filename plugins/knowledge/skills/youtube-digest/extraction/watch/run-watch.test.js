import { beforeEach, describe, expect, it, vi } from "vitest";

const recoverSpy = vi.fn(() => 0);

vi.mock("./recover-watch-bootstrap.js", () => ({
  recoverWatchBootstrapCli: (argv) => recoverSpy(argv),
}));

vi.mock("./detect-recoverable-bootstrap.js", () => ({
  detectRecoverableBootstrap: () => ({
    recoverable: true,
    tempSession: {
      workDir: "/tmp/work",
      framesDir: "/tmp/frames",
      contactSheetsDir: "/tmp/sheets",
    },
  }),
}));

const { runWatchCli } = await import("./run-watch.js");

describe("runWatchCli --recover argv alignment", () => {
  beforeEach(() => recoverSpy.mockClear());

  it("passes the four recovery paths at argv positions 2-5 (process.argv CLI convention)", async () => {
    await runWatchCli(["node", "run-watch.js", "--recover", "/tmp/slice"]);

    expect(recoverSpy).toHaveBeenCalledOnce();
    const argv = recoverSpy.mock.calls[0][0];
    // recover-watch-bootstrap.js reads sliceDir/workDir/framesDir/contactSheetsDir
    // from argv[2..5]. Before the fix the synthetic array started at the first
    // real arg, shifting everything one position left and leaving argv[5]
    // undefined (a TypeError in path.resolve there).
    expect(argv[2]).toBe("/tmp/slice");
    expect(argv[3]).toBe("/tmp/work");
    expect(argv[4]).toBe("/tmp/frames");
    expect(argv[5]).toBe("/tmp/sheets");
  });
});
