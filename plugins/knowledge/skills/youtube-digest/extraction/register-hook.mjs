/**
 * Registers the data-directory resolve hook for the child node process.
 * Loaded via `node --import register-hook.mjs <script>` from run.mjs — resolve
 * hooks run off-thread and must be registered, not imported inline.
 */
import { register } from "node:module";

register("./resolve-hook.mjs", import.meta.url);
