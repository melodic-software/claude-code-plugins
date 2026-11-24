import { describe, expect, it } from "vitest";

import { resolveSourceAdapter, SOURCE_MODULES, sourceAdapters, supportedHosts } from "./registry.js";
import { findHostCollisions } from "./shared-adapter-suite.js";

const CANONICAL_EXAMPLE_URLS = {
  youtube: "https://www.youtube.com/watch?v=7zZy1QTvokM",
  x: "https://x.com/someuser/status/1720000000000000000",
};

describe("full-registry conformance", () => {
  it("every registered adapter has a canonical example URL on file", () => {
    const adapters = sourceAdapters();
    for (const adapter of adapters) {
      expect(
        CANONICAL_EXAMPLE_URLS[adapter.id],
        `registered adapter "${adapter.id}" has no canonical example URL — add it to CANONICAL_EXAMPLE_URLS`,
      ).toBeTruthy();
    }
    const registeredIds = adapters.map((adapter) => adapter.id);
    for (const id of Object.keys(CANONICAL_EXAMPLE_URLS)) {
      expect(registeredIds, `stale example URL row "${id}"`).toContain(id);
    }
  });

  it("each canonical example URL round-trips to its own adapter with a positive claim", () => {
    for (const [id, url] of Object.entries(CANONICAL_EXAMPLE_URLS)) {
      const adapter = resolveSourceAdapter(url);
      expect(adapter.id, url).toBe(id);
      const claim = adapter.matchUrl(url);
      expect(claim, url).not.toBeNull();
      expect(resolveSourceAdapter(String(claim?.canonicalUrl)).id, url).toBe(id);
    }
  });

  it("no two registered adapters claim the same or overlapping hosts", () => {
    expect(findHostCollisions([...sourceAdapters()])).toEqual([]);
  });

  it("the registry map and the adapters' declared hosts stay in lockstep", () => {
    for (const [host, module] of Object.entries(SOURCE_MODULES)) {
      expect([...module.adapter.hosts], `registry key "${host}"`).toContain(host);
    }
    const declaredHosts = sourceAdapters().flatMap((adapter) => [...adapter.hosts]);
    expect([...supportedHosts()].sort()).toEqual(declaredHosts.sort());
  });
});
