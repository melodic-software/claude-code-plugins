import { MiroApi } from "@mirohq/miro-api";
import { describe, expect, it, vi } from "vitest";

import { createMiroClients, isTokenUnset, MISSING_TOKEN_MESSAGE } from "./miro-client.js";

describe("isTokenUnset", () => {
  // biome-ignore lint/suspicious/noTemplateCurlyInString: the literal unexpanded user_config text is the input under test.
  const unset = [undefined, "", "   ", "${user_config.miro_api_token}"];

  it.each(unset)("treats %j as unset", (v) => {
    expect(isTokenUnset(v)).toBe(true);
  });

  it("treats a real token as set", () => {
    expect(isTokenUnset("abc123")).toBe(false);
  });
});

describe("createMiroClients", () => {
  it("returns real clients when a token is set", () => {
    expect(createMiroClients("abc123").api).toBeInstanceOf(MiroApi);
  });

  it("returns clients whose calls throw the setup guidance when the token is unset", () => {
    const { api, lowLevel } = createMiroClients("");
    expect(() => api.getBoard("b")).toThrow(MISSING_TOKEN_MESSAGE);
    expect(() => lowLevel.createBoard({})).toThrow(MISSING_TOKEN_MESSAGE);
  });

  it("does not exit the process when the token is unset", () => {
    const exit = vi.spyOn(process, "exit");
    createMiroClients("");
    expect(exit).not.toHaveBeenCalled();
  });
});
