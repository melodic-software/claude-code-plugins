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

export function isTokenUnset(token: string | undefined): boolean {
  const value = token?.trim();
  return !value || value.startsWith("${user_config.");
}

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
