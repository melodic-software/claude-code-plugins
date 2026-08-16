/**
 * Contract-fixture adapter: a complete minimal source adapter on a reserved
 * example host, used to prove two properties of the conformance surface:
 *
 * 1. Capability declarations skew CLOSED — an adapter omitting EVERY optional
 *    capability passes the full shared suite (absence is a declaration, not a
 *    failure).
 * 2. The suite bites (mutation probes): deleting a required method, mutating
 *    an arity, or claiming an owned host all fail the corresponding gate.
 */

import { describe, expect, it } from "vitest";

import {
  createAcquisitionEnvelope,
  createSourceAdapter,
  REQUIRED_METHODS,
  validateAdapter,
} from "./adapter-contract.js";
import { sourceAdapters } from "./registry.js";
import { describeSourceAdapterContract, findHostCollisions } from "./shared-adapter-suite.js";

const FIXTURE_HOST = "fixture.example";
const CLIP_PATH_PATTERN = /^\/clip\/([A-Za-z0-9_-]+)$/;

/** @param {string} url */
function parseClipId(url) {
  try {
    const parsed = new URL(url);
    const hostname = parsed.hostname.toLowerCase();
    if (hostname !== FIXTURE_HOST && !hostname.endsWith(`.${FIXTURE_HOST}`)) {
      return null;
    }
    const match = CLIP_PATH_PATTERN.exec(parsed.pathname);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

/**
 * A fully contract-conforming spec whose `capabilities` object omits EVERY
 * optional capability. Returned fresh per call so mutation probes can delete
 * from it without cross-test bleed.
 */
function fixtureSpec() {
  return {
    id: "fixture",
    hosts: [FIXTURE_HOST],
    extractorArgs: null,
    allowedExtractors: null,
    captionClass: "platform-asr",
    errorPatterns: { retryable: [], fatal: [], loginRequired: [] },
    transcriptStrategy: "captions",
    capabilities: {},
    matchUrl: (url) => {
      const clipId = parseClipId(url);
      if (!clipId) return null;
      return { sliceKey: clipId, canonicalUrl: `https://${FIXTURE_HOST}/clip/${clipId}` };
    },
    extractSliceKey: (url, metadata) => {
      const clipId = parseClipId(url);
      if (clipId) return clipId;
      return metadata && typeof metadata.id === "string" && metadata.id ? metadata.id : null;
    },
    acquire: async (_url, context) => ({
      success: true,
      data: createAcquisitionEnvelope({
        entries: [],
        metadata: { id: "clip0", title: "Fixture Clip", description: "" },
        workDir: context.workDir,
      }),
    }),
    harvestLinks: (_metadata) => [],
    acceptForEnqueue: (url) => {
      const clipId = parseClipId(url);
      if (!clipId) {
        return {
          ok: false,
          note: "not a fixture clip URL",
          reason: "URL does not resolve to a fixture clip id",
        };
      }
      return { ok: true, key: clipId };
    },
  };
}

// Item B: the capability-omitting fixture adapter passes the ENTIRE shared
// suite — optional-capability absence is a declaration, never a failure.
describeSourceAdapterContract(createSourceAdapter(fixtureSpec()), {
  claimedUrls: [
    { url: `https://${FIXTURE_HOST}/clip/abc_123`, sliceKey: "abc_123" },
    { url: `https://www.${FIXTURE_HOST}/clip/abc_123`, sliceKey: "abc_123" },
  ],
  unclaimedUrls: [
    `https://${FIXTURE_HOST}/about`,
    "https://example.com/clip/abc_123",
    "not a url",
  ],
  harvestMetadata: { id: "clip0", title: "Fixture Clip", description: "" },
});

describe("capability skew (closed by default)", () => {
  it("an adapter omitting every optional capability validates cleanly and freezes empty", () => {
    const adapter = createSourceAdapter(fixtureSpec());
    expect(validateAdapter(adapter)).toEqual([]);
    expect(adapter.capabilities).toEqual({});
    // Shared machinery treats absence as false — the === true reads it uses
    // resolve to false for every omitted capability.
    expect(adapter.capabilities.comments === true).toBe(false);
    expect(adapter.capabilities.browserCookieFallback === true).toBe(false);
    expect(adapter.capabilities.mediaOptional === true).toBe(false);
  });
});

describe("mutation probes: the suite and the collision test bite", () => {
  it("deleting any required method from a test double fails the suite's contract gate", () => {
    for (const method of REQUIRED_METHODS) {
      const mutated = fixtureSpec();
      delete mutated[method];
      const violations = validateAdapter(mutated);
      expect(
        violations.some((violation) => violation.includes(`"${method}"`)),
        method,
      ).toBe(true);
      // The suite's first assertion is validateAdapter(adapter) === [] — and
      // the factory refuses to even construct the mutant.
      expect(() => createSourceAdapter(mutated), method).toThrow(method);
    }
  });

  it("mutating a required method's arity fails the contract gate", () => {
    const mutated = fixtureSpec();
    mutated.harvestLinks = () => [];
    expect(validateAdapter(mutated).some((v) => v.includes("harvestLinks"))).toBe(true);
  });

  it("registering a second adapter claiming x.com fails the collision test", () => {
    const squatter = createSourceAdapter({
      ...fixtureSpec(),
      id: "x-squatter",
      hosts: ["x.com"],
    });
    const collisions = findHostCollisions([...sourceAdapters(), squatter]);
    expect(collisions.length).toBeGreaterThan(0);
    expect(collisions.join("\n")).toContain("x.com");
    expect(collisions.join("\n")).toContain("x-squatter");
  });

  it("a subdomain claim overlapping an owned host collides too", () => {
    const subSquatter = createSourceAdapter({
      ...fixtureSpec(),
      id: "sub-squatter",
      hosts: ["video.x.com"],
    });
    expect(findHostCollisions([...sourceAdapters(), subSquatter]).length).toBeGreaterThan(0);
  });
});
