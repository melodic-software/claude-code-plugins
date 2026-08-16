/**
 * Queue-preflight fail-closed branch: an adapter that ACCEPTS a URL for
 * enqueue but then DECLINES to claim it (`matchUrl` → null) must reject the
 * row without ever spawning a probe — mirroring registry dispatch, a raw URL
 * the adapter did not positively claim is never probed. No real adapter can
 * reach this branch (their gates share one grammar), so the resolver is
 * mocked with a deliberately inconsistent fixture adapter.
 */

import { describe, expect, it, vi } from "vitest";

import { preflightVideo } from "./preflight-metadata.js";

vi.mock("../adapters/registry.js", async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    resolveSourceAdapter: vi.fn(() => ({
      id: "inconsistent-fixture",
      hosts: ["fixture.example"],
      extractorArgs: null,
      allowedExtractors: null,
      captionClass: "platform-asr",
      errorPatterns: { retryable: [], fatal: [], loginRequired: [] },
      transcriptStrategy: "captions",
      capabilities: {},
      matchUrl: () => null,
      extractSliceKey: () => "clip0",
      acquire: async () => ({ success: false, error: "never reached" }),
      harvestLinks: () => [],
      acceptForEnqueue: () => ({ ok: true, key: "clip0" }),
    })),
  };
});

describe("preflight null-matchUrl-claim branch", () => {
  it("fails closed when the adapter accepts enqueue but declines the claim — no probe is spawned", async () => {
    const spawn = vi.fn();
    const result = await preflightVideo("https://fixture.example/clip/clip0", { spawn });

    expect(result.ok).toBe(false);
    expect(result.status).toBe("invalid-url");
    expect(result.action).toBe("reject");
    expect(result.note).toContain("not claimed by source adapter");
    expect(result.reason).toContain("declined to claim");
    expect(spawn).not.toHaveBeenCalled();
  });
});
