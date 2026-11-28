import { registerHooks } from "node:module";

export { OptionsError, readOperatorOptions } from "../../lib/plugin-options.mjs";
export const managedSettingsFiles = () => [];
export const resolveInstall = () => ({ pluginId: null, name: null, userSettings: null });

const real = import.meta.resolve("../../lib/plugin-options.mjs");
registerHooks({
  resolve(specifier, context, next) {
    const resolved = next(specifier, context);
    return resolved.url === real && context.parentURL !== import.meta.url ? { ...resolved, url: import.meta.url } : resolved;
  },
});
