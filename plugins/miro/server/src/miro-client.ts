import { MiroApi, MiroLowlevelApi } from "@mirohq/miro-api";

import { writeStderr } from "./stderr.js";

export interface MiroClients {
  api: MiroApi;
  lowLevel: MiroLowlevelApi;
}

export function createMiroClients(): MiroClients {
  const token = process.env["MIRO_API_TOKEN"];
  if (!token) {
    writeStderr(
      "MIRO_API_TOKEN environment variable is required. " +
        "Get one from https://miro.com/app/settings/user-profile/apps",
    );
    process.exit(1);
  }
  return {
    api: new MiroApi(token),
    lowLevel: new MiroLowlevelApi(token),
  };
}
