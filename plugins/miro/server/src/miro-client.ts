import { MiroApi, MiroLowlevelApi } from "@mirohq/miro-api";

export interface MiroClients {
  api: MiroApi;
  lowLevel: MiroLowlevelApi;
}

export const MISSING_TOKEN_MESSAGE =
  "The Miro API token (miro_api_token) is not set. " +
  "Run `/plugin configure miro@melodic-software` to enter it, then `/reload-plugins`. " +
  "Get a token from https://miro.com/app/settings/user-profile/apps. " +
  "Without the plugin's user config, set MIRO_API_TOKEN in the server's environment.";

// An unset user_config option may reach the server as no variable, an empty string, or the
// unexpanded `${user_config.miro_api_token}` text; all three mean "no token".
export function isTokenUnset(token: string | undefined): boolean {
  return !token?.trim() || token.trim().startsWith("${user_config.");
}

// Every method access throws, so each tool call fails with the guidance instead of the
// server exiting at startup.
function unavailable<T extends object>(): T {
  return new Proxy({} as T, {
    get: () => () => {
      throw new Error(MISSING_TOKEN_MESSAGE);
    },
  });
}

export function createMiroClients(token = process.env["MIRO_API_TOKEN"]): MiroClients {
  if (token === undefined || isTokenUnset(token)) {
    return { api: unavailable<MiroApi>(), lowLevel: unavailable<MiroLowlevelApi>() };
  }
  return { api: new MiroApi(token), lowLevel: new MiroLowlevelApi(token) };
}
