/**
 * Full-registry conformance: insurance for adapter three. A new adapter lands
 * by adding a registry row and a canonical example URL here; these tests then
 * prove at CI time that its URLs dispatch to IT (round-trip), that no two
 * adapters claim the same or overlapping hosts, and that the registry map and
 * the adapters' declared hosts stay in lockstep.
 */

import { describe, expect, it } from "vitest";

import { resolveSourceAdapter, SOURCE_MODULES, sourceAdapters, supportedHosts } from "./registry.js";
import { findHostCollisions } from "./shared-adapter-suite.js";

/**
 * One canonical example URL per registered adapter id. A registered adapter
 * with no row here fails the coverage test below — add the row with the
 * adapter, never after.
 */
const CANONICAL_EXAMPLE_URLS = {
  youtube: "https://www.youtube.com/watch?v=7zZy1QTvokM",
  x: "https://x.com/someuser/status/1720000000000000000",
};

describe("full-registry conformance", () => {
  it("every registered adapter has a canonical example URL on file", () => {
    for (const adapter of sourceAdapters()) {
      expect(
        CANONICAL_EXAMPLE_URLS[adapter.id],
        `registered adapter "${adapter.id}" has no canonical example URL — add it to CANONICAL_EXAMPLE_URLS`,
      ).toBeTruthy();
    }
    // …and no stale rows for adapters that no longer exist.
    const registeredIds = sourceAdapters().map((adapter) => adapter.id);
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
      // The canonical URL the claim yields still dispatches to the same
      // adapter — canonicalization can never re-route a URL across sources.
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
