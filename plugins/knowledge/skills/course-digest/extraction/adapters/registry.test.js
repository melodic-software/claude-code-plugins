import { describe, expect, it } from "vitest";

import { resolveAdapter } from "../lib/config.js";
import { validateAdapter } from "./adapter-contract.js";
import * as dometrain from "./dometrain.js";
import { lookupAdapter, PLATFORM_ADAPTERS } from "./registry.js";
import * as teachable from "./teachable.js";

describe("PLATFORM_ADAPTERS", () => {
  it("is frozen", () => {
    expect(Object.isFrozen(PLATFORM_ADAPTERS)).toBe(true);
  });

  it.each(Object.entries(PLATFORM_ADAPTERS))("%s satisfies the adapter contract", (id, mod) => {
    expect(validateAdapter(mod, id).success).toBe(true);
  });
});

describe("resolveAdapter", () => {
  it("returns the statically imported module for each registered platform", async () => {
    expect(await resolveAdapter("dometrain")).toBe(dometrain);
    expect(await resolveAdapter("teachable")).toBe(teachable);
  });

  it.each([
    "nonexistent-platform",
    "constructor",
    "__proto__",
    "toString",
    "hasOwnProperty",
    "adapter-contract",
    "auth-session",
    "registry",
    "../lib/config",
    "../adapters/dometrain",
    "dometrain.js",
    "Dometrain",
    "dometrain.com",
    "",
  ])("fails closed with null for %j", async (name) => {
    expect(lookupAdapter(name)).toBeNull();
    expect(await resolveAdapter(name)).toBeNull();
  });
});
