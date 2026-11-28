import type { Register } from 'claude-code'

import { register as bedroom } from './bedroom/register.tsx'
import { createModEnablement } from './mod-hook-enabled'

/** The themes plugin: each theme lives in its own folder and registers its own hooks. */
export const register: Register = (on, options) => {
  const gate = createModEnablement(options, {
    plugin: 'themes',
    key: 'themes_enabled',
    defaultValue: true,
  })
  if (gate.isDisabledAtLoad()) return
  bedroom(on, options, gate)
}
