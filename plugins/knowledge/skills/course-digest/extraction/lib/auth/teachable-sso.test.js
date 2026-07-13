import { beforeEach, describe, expect, it } from "vitest";

import { login } from "./teachable-sso.js";
import { createMockPage } from "./test-helpers.js";

describe("teachable-sso auth module", () => {
  let page;

  beforeEach(async () => {
    page = createMockPage();
    await login(page, "user@test.com", "pass123", "https://school.teachable.com/sign_in");
  });

  it("should navigate to login URL", () => {
    expect(page.actions[0]).toEqual({ type: "goto", url: "https://school.teachable.com/sign_in" });
  });

  it("should fill email and password", () => {
    const fills = page.actions.filter((a) => a.type === "fill");
    expect(fills).toHaveLength(2);
    expect(fills[0].value).toBe("user@test.com");
    expect(fills[1].value).toBe("pass123");
  });

  it("should click submit once", () => {
    const clicks = page.actions.filter((a) => a.type === "click");
    expect(clicks).toHaveLength(1);
  });
});
