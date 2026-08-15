import { describe, expect, it } from "vitest";

import {
  classifyErrorDetail,
  createAcquisitionEnvelope,
  createSourceAdapter,
  FatalSourceError,
  LoginRequiredError,
  REQUIRED_METHODS,
  RetryableSourceError,
  singleEntry,
  UnsupportedSourceError,
  validateAdapter,
} from "./adapter-contract.js";

/** Minimal contract-conforming spec for validation tests. */
function validSpec() {
  return {
    id: "stub",
    hosts: ["stub.example"],
    extractorArgs: null,
    captionClass: "platform-asr",
    errorPatterns: { retryable: [], fatal: [/gone/i], loginRequired: [/log in/i] },
    transcriptStrategy: "captions",
    capabilities: {},
    matchUrl: (url) => ({ sliceKey: url, canonicalUrl: url }),
    extractSliceKey: (url, _metadata) => url,
    acquire: async (_url, _context) => ({ success: true }),
    harvestLinks: (_metadata) => [],
    acceptForEnqueue: (_url) => ({ ok: true }),
  };
}

function entry(overrides = {}) {
  return { mediaPath: "", captionPaths: [], metadataPath: "", caption: null, ...overrides };
}

const METADATA = { id: "x1", title: "T", description: "" };

describe("error taxonomy", () => {
  it("keeps the dispatch-level error outside the adapter error hierarchy", () => {
    const err = new UnsupportedSourceError("https://vimeo.com/1", ["youtube.com"]);
    expect(err).toBeInstanceOf(Error);
    expect(err).not.toBeInstanceOf(RetryableSourceError);
    expect(err).not.toBeInstanceOf(FatalSourceError);
    expect(err).not.toBeInstanceOf(LoginRequiredError);
    expect(err.message).toContain("youtube.com");
    expect(err.supportedHosts).toEqual(["youtube.com"]);
  });

  it("carries degradation detail as metadata on the retryable type", () => {
    const bare = new RetryableSourceError("throttled");
    expect(bare.degradation).toBeNull();
    const degraded = new RetryableSourceError("throttled", { syndicationFallback: true });
    expect(degraded.degradation).toEqual({ syndicationFallback: true });
  });
});

describe("classifyErrorDetail", () => {
  const patterns = { retryable: [/429/], fatal: [/gone/i], loginRequired: [/log in/i] };

  it("classifies with login-required > fatal > retryable precedence", () => {
    expect(classifyErrorDetail(patterns, "please log in — gone")).toBe("login-required");
    expect(classifyErrorDetail(patterns, "video gone")).toBe("fatal");
    expect(classifyErrorDetail(patterns, "HTTP 429")).toBe("retryable");
  });

  it("returns null for unclassified or empty detail", () => {
    expect(classifyErrorDetail(patterns, "mystery")).toBeNull();
    expect(classifyErrorDetail(patterns, "")).toBeNull();
  });
});

describe("createAcquisitionEnvelope", () => {
  it("accepts a 0-entry envelope as well-formed (metadata-only, never null)", () => {
    const envelope = createAcquisitionEnvelope({ entries: [], metadata: METADATA, workDir: "/w" });
    expect(envelope).not.toBeNull();
    expect(envelope.entries).toEqual([]);
    expect(envelope.metadata).toBe(METADATA);
  });

  it("accepts 1 and N entries and freezes the result", () => {
    const one = createAcquisitionEnvelope({
      entries: [entry({ mediaPath: "/w/a.mp4" })],
      metadata: METADATA,
      workDir: "/w",
    });
    expect(one.entries).toHaveLength(1);
    expect(Object.isFrozen(one)).toBe(true);
    expect(Object.isFrozen(one.entries)).toBe(true);
    expect(Object.isFrozen(one.entries[0])).toBe(true);

    const many = createAcquisitionEnvelope({
      entries: [entry(), entry(), entry()],
      metadata: METADATA,
      workDir: "/w",
    });
    expect(many.entries).toHaveLength(3);
  });

  it("rejects malformed parts", () => {
    expect(() =>
      createAcquisitionEnvelope({ entries: null, metadata: METADATA, workDir: "/w" }),
    ).toThrow(/entries/);
    expect(() =>
      createAcquisitionEnvelope({
        entries: [{ captionPaths: [], metadataPath: "" }],
        metadata: METADATA,
        workDir: "/w",
      }),
    ).toThrow(/mediaPath/);
    expect(() =>
      createAcquisitionEnvelope({ entries: [], metadata: null, workDir: "/w" }),
    ).toThrow(/metadata/);
  });
});

describe("singleEntry", () => {
  it("collapses only exact arity 1", () => {
    const one = createAcquisitionEnvelope({
      entries: [entry({ mediaPath: "/w/a.mp4" })],
      metadata: METADATA,
      workDir: "/w",
    });
    expect(singleEntry(one)?.mediaPath).toBe("/w/a.mp4");

    const zero = createAcquisitionEnvelope({ entries: [], metadata: METADATA, workDir: "/w" });
    expect(singleEntry(zero)).toBeNull();

    const two = createAcquisitionEnvelope({
      entries: [entry(), entry()],
      metadata: METADATA,
      workDir: "/w",
    });
    expect(singleEntry(two)).toBeNull();
  });
});

describe("validateAdapter", () => {
  it("passes a minimal conforming spec, including one omitting every optional capability", () => {
    expect(validateAdapter(validSpec())).toEqual([]);
  });

  it("flags each missing required method", () => {
    for (const method of REQUIRED_METHODS) {
      const spec = validSpec();
      delete spec[method];
      const violations = validateAdapter(spec);
      expect(violations.some((v) => v.includes(`"${method}"`))).toBe(true);
    }
  });

  it("flags wrong declared arity (defaulted parameters included)", () => {
    const spec = validSpec();
    spec.extractSliceKey = (url) => url;
    expect(validateAdapter(spec).some((v) => v.includes("extractSliceKey"))).toBe(true);

    const defaulted = validSpec();
    defaulted.acquire = async (url, context = {}) => ({ success: true, url, context });
    expect(validateAdapter(defaulted).some((v) => v.includes("acquire"))).toBe(true);
  });

  it("rejects unknown capabilities (closed by default) and the reserved content-claim capability", () => {
    const unknown = validSpec();
    unknown.capabilities = { teleport: true };
    expect(validateAdapter(unknown).some((v) => v.includes("teleport"))).toBe(true);

    const reserved = validSpec();
    reserved.capabilities = { contentClaim: true };
    expect(validateAdapter(reserved).some((v) => v.includes("contentClaim"))).toBe(true);

    const reservedOff = validSpec();
    reservedOff.capabilities = { contentClaim: false };
    expect(validateAdapter(reservedOff)).toEqual([]);
  });

  it("rejects malformed declared attributes", () => {
    const badHosts = validSpec();
    badHosts.hosts = ["https://youtube.com"];
    expect(validateAdapter(badHosts).some((v) => v.includes("hosts"))).toBe(true);

    const badExtractor = validSpec();
    badExtractor.extractorArgs = 42;
    expect(validateAdapter(badExtractor).some((v) => v.includes("extractorArgs"))).toBe(true);

    const badStrategy = validSpec();
    badStrategy.transcriptStrategy = "telepathy";
    expect(validateAdapter(badStrategy).some((v) => v.includes("transcriptStrategy"))).toBe(true);

    const badPatterns = validSpec();
    badPatterns.errorPatterns = { retryable: [], fatal: ["gone"], loginRequired: [] };
    expect(validateAdapter(badPatterns).some((v) => v.includes("errorPatterns.fatal"))).toBe(true);

    const extraPatternClass = validSpec();
    extraPatternClass.errorPatterns = {
      retryable: [],
      fatal: [],
      loginRequired: [],
      degraded: [],
    };
    expect(validateAdapter(extraPatternClass).some((v) => v.includes("degraded"))).toBe(true);
  });
});

describe("createSourceAdapter", () => {
  it("freezes the adapter and its declared collections", () => {
    const adapter = createSourceAdapter(validSpec());
    expect(Object.isFrozen(adapter)).toBe(true);
    expect(Object.isFrozen(adapter.hosts)).toBe(true);
    expect(Object.isFrozen(adapter.errorPatterns)).toBe(true);
    expect(Object.isFrozen(adapter.capabilities)).toBe(true);
  });

  it("throws listing every violation", () => {
    const spec = validSpec();
    delete spec.acquire;
    spec.capabilities = { teleport: true };
    expect(() => createSourceAdapter(spec)).toThrow(/acquire[\s\S]*teleport/);
  });
});
