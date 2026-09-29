/** `node --import` entry for tests: swaps the `playwright` package for a stub so no browser can launch. */
import { register } from "node:module";

register("./playwright-stub-hook.mjs", import.meta.url);
