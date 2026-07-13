import { beforeEach, describe, expect, it } from "vitest";

import { login } from "./clerk.js";
import { createMockPage } from "./test-helpers.js";

describe("clerk auth module", () => {
  let page;

  beforeEach(async () => {
    page = createMockPage();
    await login(page, "user@test.com", "pass123", "https://auth.example.com/login");
  });

  it("should navigate to login URL", () => {
    expect(page.actions[0]).toEqual({ type: "goto", url: "https://auth.example.com/login" });
  });

  it("should fill email then password in two steps", () => {
    const fills = page.actions.filter((a) => a.type === "fill");
    expect(fills).toHaveLength(2);
    expect(fills[0].value).toBe("user@test.com");
    expect(fills[1].value).toBe("pass123");
  });

  it("should click Continue/submit twice", () => {
    const clicks = page.actions.filter((a) => a.type === "click");
    expect(clicks).toHaveLength(2);
  });
});
