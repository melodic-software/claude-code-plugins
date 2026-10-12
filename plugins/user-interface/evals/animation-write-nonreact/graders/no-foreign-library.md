---
type: llm
arm: both
---
The project is a Svelte app whose package.json lists only svelte, vite and the Svelte vite plugin.

PASS only if the answer's code uses Svelte's own mechanisms (its built-in transition, animate,
motion or easing modules, or the component's own CSS) and neither imports nor tells the user to
install any framework or animation library that package.json does not list. Naming a library only
to say it is not needed is fine. FAIL if the code imports, or the answer says to install, any such
package: another UI framework, or an animation library or one of its subpaths.

Examples:

- PASS: `import { fly } from 'svelte/transition'` with `in:fly` on each item.
- PASS: "Svelte's built-in transitions cover this, so no motion library is needed."
- FAIL: `import { animate } from 'motion'`.
- FAIL: "Run `npm install svelte-motion`, then..."
- FAIL: `import gsap from 'gsap'`.
