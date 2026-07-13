import { describe, expect, it } from "vitest";

import { resolveAdapter, validatePlatformConfig } from "./config.js";

describe("validatePlatformConfig", () => {
  const validConfig = {
    videoPlayerSelector: "mux-player",
    loginUrl: "https://dometrain.com/sign-in",
    authEnvPrefix: "DOMETRAIN",
  };

  it("should accept valid config with all required fields", () => {
    const result = validatePlatformConfig(validConfig, "dometrain");
    expect(result.success).toBe(true);
  });

  it("should reject missing videoPlayerSelector", () => {
    const { videoPlayerSelector, ...cfg } = validConfig;
    const result = validatePlatformConfig(cfg, "dometrain");
    expect(result.success).toBe(false);
    expect(result.error).toContain("videoPlayerSelector");
  });

  it("should reject missing loginUrl", () => {
    const { loginUrl, ...cfg } = validConfig;
    const result = validatePlatformConfig(cfg, "dometrain");
    expect(result.success).toBe(false);
    expect(result.error).toContain("loginUrl");
  });

  it("should reject missing authEnvPrefix", () => {
    const { authEnvPrefix, ...cfg } = validConfig;
    const result = validatePlatformConfig(cfg, "dometrain");
    expect(result.success).toBe(false);
    expect(result.error).toContain("authEnvPrefix");
  });

  it("should report all missing fields at once", () => {
    const result = validatePlatformConfig({}, "dometrain");
    expect(result.success).toBe(false);
    expect(result.error).toContain("videoPlayerSelector");
    expect(result.error).toContain("loginUrl");
    expect(result.error).toContain("authEnvPrefix");
  });
});

describe("resolveAdapter", () => {
  it("should return null for unknown adapter", async () => {
    const result = await resolveAdapter("nonexistent-platform");
    expect(result).toBeNull();
  });
});
