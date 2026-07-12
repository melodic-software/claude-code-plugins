import { describe, expect, it } from "vitest";

import {
  deriveSemanticNameFromGapNote,
  forbiddenSynthesisFileNameReason,
  isForbiddenPipelineSessionSlug,
  isPipelinePlaceholderGapNote,
  isStubQualityAuditNote,
} from "./synthesis-filename.js";

describe("forbiddenSynthesisFileNameReason", () => {
  it("rejects legacy pipeline tokens", () => {
    expect(forbiddenSynthesisFileNameReason("at-12m30s-anchor.png")).toBeTruthy();
    expect(forbiddenSynthesisFileNameReason("dens-code-m478.png")).toBeTruthy();
    expect(forbiddenSynthesisFileNameReason("code-code-28134.png")).toBeTruthy();
    expect(forbiddenSynthesisFileNameReason("dens-scene0003.png")).toBeTruthy();
  });

  it("accepts semantic names", () => {
    expect(forbiddenSynthesisFileNameReason("network-diagram-architecture-slide.png")).toBeNull();
    expect(forbiddenSynthesisFileNameReason("ceo-dashboard-objectives-table-ui.png")).toBeNull();
  });
});

describe("isForbiddenPipelineSessionSlug", () => {
  it("rejects pipeline filler slugs", () => {
    expect(isForbiddenPipelineSessionSlug("densification-topup")).toBe(true);
    expect(isForbiddenPipelineSessionSlug("pipeline-bulk")).toBe(true);
  });

  it("accepts slice-derived session slugs", () => {
    expect(isForbiddenPipelineSessionSlug("opening-keynote")).toBe(false);
  });
});

describe("isPipelinePlaceholderGapNote", () => {
  it("detects tooling placeholder gap notes", () => {
    expect(isPipelinePlaceholderGapNote("Frame in code densification window.")).toBe(true);
    expect(
      isPipelinePlaceholderGapNote("On-screen metrics table with quarterly revenue figures"),
    ).toBe(false);
  });
});

describe("deriveSemanticNameFromGapNote", () => {
  it("slugifies gap notes", () => {
    const name = deriveSemanticNameFromGapNote(
      "On-screen executive dashboard with objectives table and KPI cards",
    );
    expect(name).toMatch(/\.png$/);
    expect(forbiddenSynthesisFileNameReason(name)).toBeNull();
  });
});

describe("isStubQualityAuditNote", () => {
  it("rejects stub tokens", () => {
    expect(isStubQualityAuditNote("audit")).toBe(true);
    expect(isStubQualityAuditNote("On-screen metrics: 815k cache hits not in transcript")).toBe(
      false,
    );
  });
});
