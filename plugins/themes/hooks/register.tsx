import type { Register } from 'claude-code'

import { register as bedroom } from './bedroom/register.tsx'

/** The themes plugin: each theme lives in its own folder and registers its own hooks. */
export const register: Register = (on, options) => bedroom(on, options)
