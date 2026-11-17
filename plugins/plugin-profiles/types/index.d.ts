// An in-session switch whose on entries are written: 'armed' until the turn ends, 'reloading' once
// /reload-plugins is queued, then cleared when the off entries are written.
export type Switch = { profile: string; phase: 'armed' | 'reloading'; off?: string[]; kind?: 'clear'; keeps?: string }

export type PickerEntry = { value: string; label: string }

declare module 'claude-code' {
  interface PluginState {
    'plugin-profiles': { switch: Switch | null; picker: PickerEntry[] }
  }
}
